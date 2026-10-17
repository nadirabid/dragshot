/**
 * The Lookit bridge.
 *
 * A small, local-only server inside the DSH host. It exposes the one thing an
 * external capture app needs and nothing else: list sessions, and send one
 * screenshot plus note to a new or most recently used session.
 *
 * Transport is newline-delimited JSON over a Unix domain socket. The socket
 * directory and file are owner-only; no TCP port is opened.
 *
 * Request:  {"id": "...", "method": "send", "params": {...}}
 * Response: {"id": "...", "ok": true, "result": {...}}
 *           {"id": "...", "ok": false, "error": {"code": "...", "message": "..."}}
 */

import { randomUUID } from 'node:crypto'
import { promises as fs } from 'node:fs'
import { createServer } from 'node:net'
import { homedir } from 'node:os'
import { dirname, isAbsolute, join, resolve } from 'node:path'

export const PROTOCOL = 1

const MEDIA_TYPES = new Set(['image/png', 'image/jpeg', 'image/webp', 'image/gif'])
const DEFAULT_IMAGE_BYTES = 20 * 1024 * 1024
const DEFAULT_TEXT_CHARS = 20_000
const DEFAULT_LINE_BYTES = 40 * 1024 * 1024
const DEFAULT_REQUEST_TIMEOUT_MS = 15_000
const DEFAULT_PROMPT_TIMEOUT_MS = 60_000
const DEFAULT_SOCKET_TIMEOUT_MS = 120_000

class BridgeError extends Error {
    constructor(code, message) {
        super(message)
        this.name = 'BridgeError'
        this.code = code
    }
}

/** Expand only the home-directory forms a profile config can reasonably contain. */
function expandHome(value) {
    if (typeof value !== 'string') return null
    const trimmed = value.trim()
    if (trimmed.length === 0) return null
    if (trimmed === '~') return homedir()
    if (trimmed.startsWith('~/')) return join(homedir(), trimmed.slice(2))
    return trimmed
}

/** A short title from the title projection, with a stable fallback. */
function titleOf(summary) {
    const raw = summary?.projections?.values?.title
    if (typeof raw === 'string' && raw.trim().length > 0) return raw.trim()
    return 'New session'
}

function errorPayload(error) {
    if (error instanceof BridgeError) return { code: error.code, message: error.message }
    const code = typeof error?.code === 'string' && error.code.length > 0
        ? error.code
        : 'internal'
    const message = error instanceof Error ? error.message : String(error)
    return { code, message: message.slice(0, 2000) }
}

export class LookitBridge {
    #server
    #sockets = new Set()
    #stopping = false
    #logReady

    constructor({
        sessionController,
        socketPath = join(homedir(), 'Library', 'Application Support', 'Lookit', 'dsh.sock'),
        discoveryPath = join(homedir(), 'Library', 'Application Support', 'Lookit', 'dsh-bridge.json'),
        logPath = join(homedir(), 'Library', 'Logs', 'LookitDshBridge.log'),
        defaultCwd = homedir(),
        requestTimeoutMs = DEFAULT_REQUEST_TIMEOUT_MS,
        promptTimeoutMs = DEFAULT_PROMPT_TIMEOUT_MS,
        socketTimeoutMs = DEFAULT_SOCKET_TIMEOUT_MS,
        maxImageBytes = DEFAULT_IMAGE_BYTES,
        maxTextChars = DEFAULT_TEXT_CHARS,
        maxLineBytes = DEFAULT_LINE_BYTES,
        logger = undefined,
        now = () => new Date().toISOString(),
    } = {}) {
        if (typeof socketPath !== 'string' || socketPath.length === 0) {
            throw new TypeError('LookitBridge: socketPath is required')
        }
        this.sessionController = sessionController
        this.socketPath = socketPath
        this.discoveryPath = discoveryPath
        this.logPath = logPath
        this.defaultCwd = defaultCwd
        this.requestTimeoutMs = requestTimeoutMs
        this.promptTimeoutMs = promptTimeoutMs
        this.socketTimeoutMs = socketTimeoutMs
        this.maxImageBytes = maxImageBytes
        this.maxTextChars = maxTextChars
        this.maxLineBytes = maxLineBytes
        this.logger = logger
        this.now = now
    }

    get started() {
        return this.#server !== undefined
    }

    /**
     * Create the socket and publish the discovery file. Safe to call once; a
     * second call is a no-op.
     */
    async start() {
        if (this.#server !== undefined) return
        if (Buffer.byteLength(this.socketPath) > 100) {
            throw new BridgeError('socket_path_too_long',
                'The Lookit socket path must fit in a Unix socket address (100 bytes).')
        }

        await fs.mkdir(dirname(this.socketPath), { recursive: true, mode: 0o700 })
        await fs.chmod(dirname(this.socketPath), 0o700).catch(() => {})
        await fs.mkdir(dirname(this.discoveryPath), { recursive: true, mode: 0o700 })
        await fs.chmod(dirname(this.discoveryPath), 0o700).catch(() => {})
        await fs.unlink(this.socketPath).catch((error) => {
            if (error?.code !== 'ENOENT') throw error
        })

        const server = createServer((socket) => this.#accept(socket))
        server.maxConnections = 8
        server.on('error', (error) => {
            this.#log(`server error: ${error?.message ?? error}`)
        })

        await new Promise((resolveListening, rejectListening) => {
            const onError = (error) => {
                server.off('listening', onListening)
                rejectListening(error)
            }
            const onListening = () => {
                server.off('error', onError)
                resolveListening()
            }
            server.once('error', onError)
            server.once('listening', onListening)
            server.listen(this.socketPath)
        }).catch((error) => {
            server.close()
            throw new BridgeError('socket_listen_failed',
                `Could not listen on ${this.socketPath}: ${error?.message ?? error}`)
        })

        await fs.chmod(this.socketPath, 0o600).catch((error) => {
            this.#log(`could not chmod socket: ${error?.message ?? error}`)
        })

        const discovery = {
            protocol: PROTOCOL,
            socket: this.socketPath,
            pid: process.pid,
            startedAt: this.now(),
        }
        const temporary = `${this.discoveryPath}.${process.pid}.tmp`
        try {
            await fs.writeFile(temporary, `${JSON.stringify(discovery)}\n`, { mode: 0o600 })
            await fs.rename(temporary, this.discoveryPath)
        } catch (error) {
            await Promise.resolve(server.close()).catch(() => {})
            await fs.unlink(this.socketPath).catch(() => {})
            throw new BridgeError('discovery_write_failed',
                `Could not publish the Lookit discovery file: ${error?.message ?? error}`)
        }

        this.#server = server
        this.#stopping = false
        this.#log(`bridge listening at ${this.socketPath} (pid ${process.pid})`)
    }

    /** Close the socket and remove our discovery file, but never another instance's. */
    async stop() {
        if (this.#stopping) return
        this.#stopping = true
        for (const socket of this.#sockets) {
            try { socket.destroy() } catch { /* already closed */ }
        }
        this.#sockets.clear()
        const server = this.#server
        this.#server = undefined
        if (server !== undefined) {
            await new Promise((resolveClose) => {
                try { server.close(() => resolveClose()) } catch { resolveClose() }
            })
        }
        await fs.unlink(this.socketPath).catch(() => {})
        try {
            const raw = await fs.readFile(this.discoveryPath, 'utf8')
            const current = JSON.parse(raw)
            if (current?.pid === process.pid) await fs.unlink(this.discoveryPath)
        } catch { /* no discovery file, or someone else's */ }
        this.#log('bridge stopped')
    }

    /**
     * Normalized session rows. Subagents are excluded: a capture belongs to a
     * conversation, not to a delegated child.
     */
    async listSessions() {
        if (this.sessionController === undefined || typeof this.sessionController.list !== 'function') {
            throw new BridgeError('session_controller_unavailable',
                'The DSH session controller is not available in this profile.')
        }
        const value = await this.sessionController.list(
            AbortSignal.timeout(this.requestTimeoutMs),
        )
        // The public Host method returns { items }, while an older internal
        // caller returned a bare array. Accept both so the bridge survives the
        // shape changing at this layer.
        const summaries = Array.isArray(value) ? value : value?.items
        if (!Array.isArray(summaries)) {
            throw new BridgeError('session_list_invalid',
                'The DSH session controller returned no list.')
        }
        return summaries
            .filter((summary) => summary !== null
                && typeof summary === 'object'
                && typeof summary.sessionId === 'string'
                && summary.parentSessionId === undefined
                && summary.origin !== 'subagent')
            .map((summary) => ({
                sessionId: String(summary.sessionId),
                title: titleOf(summary),
                cwd: typeof summary.cwd === 'string' ? summary.cwd : null,
                updatedAt: Number.isFinite(summary.updatedAt) ? summary.updatedAt : 0,
                lastPromptAt: Number.isFinite(summary?.projections?.values?.sessionListMetadata?.lastPromptAt)
                    ? summary.projections.values.sessionListMetadata.lastPromptAt
                    : null,
                running: summary.running === true,
                blank: summary.blank === true,
            }))
            .sort((left, right) => (right.lastPromptAt ?? right.updatedAt)
                - (left.lastPromptAt ?? left.updatedAt))
            .slice(0, 50)
    }

    async #dispatch(method, params) {
        switch (method) {
            case 'hello':
                return {
                    protocol: PROTOCOL,
                    plugin: 'dsh-lookit',
                    pid: process.pid,
                    methods: ['hello', 'ping', 'list', 'send'],
                }
            case 'ping':
                return { pong: true, now: Date.now() }
            case 'list':
                return { items: await this.listSessions() }
            case 'send':
                return await this.#sendCapture(params ?? {})
            default:
                throw new BridgeError('unsupported', `Unknown method: ${String(method)}`)
        }
    }

    async #sendCapture(params) {
        if (params === null || typeof params !== 'object' || Array.isArray(params)) {
            throw new BridgeError('bad_request', 'params must be an object.')
        }
        const text = typeof params.text === 'string' ? params.text : ''
        if (text.length > this.maxTextChars) {
            throw new BridgeError('text_too_large',
                `The note is longer than ${this.maxTextChars} characters.`)
        }
        const image = this.#parseImage(params)
        if (text.trim().length === 0 && image === null) {
            throw new BridgeError('bad_request', 'A note or an image is required.')
        }

        const requested = typeof params.sessionId === 'string' && params.sessionId.trim().length > 0
            ? params.sessionId.trim()
            : null
        const wantsNew = params.target === 'new'
        let candidates = []
        if (requested === null) {
            try {
                candidates = await this.listSessions()
            } catch (error) {
                if (!wantsNew) throw error
                this.#log(`list failed while choosing a new-session directory: ${error?.message ?? error}`)
            }
        }

        let sessionId = requested
        let title = null
        let created = false
        let target = requested === null ? (wantsNew ? 'new' : 'recent') : 'session'

        if (sessionId === null && !wantsNew && candidates.length > 0) {
            sessionId = candidates[0].sessionId
            title = candidates[0].title
        }

        if (sessionId === null) {
            const cwd = await this.#resolveCwd(params.cwd ?? candidates[0]?.cwd)
            const value = await this.sessionController.create({ cwd })
            if (typeof value?.sessionId !== 'string' || value.sessionId.length === 0) {
                throw new BridgeError('session_create_failed',
                    'DSH created no session for this capture.')
            }
            sessionId = String(value.sessionId)
            created = true
            target = 'new'
        }

        const content = []
        if (text.trim().length > 0) content.push({ type: 'text', text })
        if (image !== null) {
            content.push({
                type: 'image',
                mediaType: image.mediaType,
                data: image.data,
                name: image.name,
            })
        }

        await this.sessionController.prompt({
            requestId: randomUUID(),
            sessionId,
            mode: params.mode === 'steer' ? 'steer' : 'queue',
            content,
        }, AbortSignal.timeout(this.promptTimeoutMs))

        this.#log(`sent session=${sessionId} target=${target} image=${image?.bytes ?? 0}B text=${text.length}c`)
        return { sessionId, title, created, target }
    }

    #parseImage(params) {
        const raw = params.imageBase64
        if (raw === undefined || raw === null) return null
        if (typeof raw !== 'string' || raw.length === 0) {
            throw new BridgeError('bad_request', 'imageBase64 must be a non-empty string.')
        }
        const mediaType = typeof params.imageMediaType === 'string'
            ? params.imageMediaType
            : 'image/png'
        if (!MEDIA_TYPES.has(mediaType)) {
            throw new BridgeError('unsupported_media_type',
                `Unsupported image type: ${mediaType}`)
        }
        const bytes = Buffer.byteLength(raw, 'base64')
        if (!Number.isFinite(bytes) || bytes <= 0) {
            throw new BridgeError('bad_request', 'imageBase64 is not valid base64 data.')
        }
        if (bytes > this.maxImageBytes) {
            throw new BridgeError('image_too_large',
                `The screenshot is larger than ${Math.round(this.maxImageBytes / (1024 * 1024))} MB.`)
        }
        const rawName = typeof params.imageName === 'string' ? params.imageName : 'lookit.png'
        const name = rawName.replace(/[\u0000-\u001f\u007f]/g, '').slice(0, 200) || 'lookit.png'
        return { mediaType, data: raw, name, bytes }
    }

    async #resolveCwd(requested) {
        const candidate = expandHome(requested) ?? expandHome(this.defaultCwd) ?? homedir()
        const absolute = isAbsolute(candidate) ? candidate : resolve(candidate)
        try {
            const stat = await fs.stat(absolute)
            if (stat.isDirectory()) return absolute
        } catch { /* fall through */ }
        return homedir()
    }

    #accept(socket) {
        socket.setNoDelay(true)
        socket.setEncoding('utf8')
        socket.setTimeout(this.socketTimeoutMs, () => socket.destroy())
        this.#sockets.add(socket)
        socket.on('close', () => { this.#sockets.delete(socket) })
        socket.on('error', () => { this.#sockets.delete(socket) })

        let buffer = ''
        let queue = Promise.resolve()
        socket.on('data', (chunk) => {
            buffer += chunk
            if (buffer.length > this.maxLineBytes) {
                this.#respond(socket, {
                    id: null,
                    ok: false,
                    error: { code: 'request_too_large', message: 'The request line is too large.' },
                })
                socket.destroy()
                return
            }
            for (;;) {
                const newline = buffer.indexOf('\n')
                if (newline < 0) break
                const line = buffer.slice(0, newline)
                buffer = buffer.slice(newline + 1)
                if (line.trim().length === 0) continue
                queue = queue
                    .then(() => this.#handleLine(line, socket))
                    .catch(() => { /* #handleLine answers its own failures */ })
            }
        })
    }

    async #handleLine(line, socket) {
        let request
        try {
            request = JSON.parse(line)
        } catch {
            this.#respond(socket, {
                id: null,
                ok: false,
                error: { code: 'bad_json', message: 'The request is not valid JSON.' },
            })
            return
        }
        const id = typeof request?.id === 'string' || typeof request?.id === 'number'
            ? request.id
            : null
        const method = typeof request?.method === 'string' ? request.method : ''
        try {
            if (method.length === 0) throw new BridgeError('bad_request', 'A method is required.')
            const result = await this.#dispatch(method, request?.params)
            this.#respond(socket, { id, ok: true, result })
        } catch (error) {
            this.#respond(socket, { id, ok: false, error: errorPayload(error) })
        }
    }

    #respond(socket, payload) {
        if (socket.destroyed) return
        try {
            socket.write(`${JSON.stringify(payload)}\n`)
        } catch { /* the client went away */ }
    }

    #log(message) {
        const line = `${this.now()} ${message}\n`
        try { this.logger?.warn?.(`lookit: ${message}`) } catch { /* logging never breaks the bridge */ }
        if (typeof this.logPath !== 'string' || this.logPath.length === 0) return
        if (this.#logReady === undefined) {
            this.#logReady = fs.mkdir(dirname(this.logPath), { recursive: true })
                .then(() => fs.appendFile(this.logPath, line, { mode: 0o600 }))
                .catch(() => {})
            return
        }
        this.#logReady = this.#logReady
            .then(() => fs.appendFile(this.logPath, line))
            .catch(() => {})
    }
}
