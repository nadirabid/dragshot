import assert from 'node:assert/strict'
import { promises as fs } from 'node:fs'
import net from 'node:net'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import test from 'node:test'
import { LookitBridge, PROTOCOL } from '../lib/bridge.js'

async function workspace() {
    const root = await fs.mkdtemp(join(tmpdir(), 'dsh-lookit-test-'))
    return {
        root,
        socket: join(root, 'dsh.sock'),
        discovery: join(root, 'dsh-bridge.json'),
        log: join(root, 'bridge.log'),
    }
}

function fakeController(items = [], { promptError, createError } = {}) {
    const calls = { list: 0, created: [], prompted: [] }
    return {
        calls,
        controller: {
            async list() {
                calls.list += 1
                return items
            },
            async create(request) {
                calls.created.push(request)
                if (createError) throw createError
                return { sessionId: `created-${calls.created.length}` }
            },
            async prompt(request) {
                calls.prompted.push(request)
                if (promptError) throw promptError
                return { accepted: true }
            },
        },
    }
}

function summary(id, title, lastPromptAt, extra = {}) {
    return {
        sessionId: id,
        updatedAt: lastPromptAt,
        running: false,
        blank: false,
        cwd: extra.cwd ?? tmpdir(),
        projections: {
            kind: 'sequenced',
            asOfSeq: 1,
            values: {
                title,
                sessionListMetadata: { blank: false, lastPromptAt },
            },
        },
        ...extra,
    }
}

async function call(socketPath, request, timeoutMs = 5000) {
    return await new Promise((resolve, reject) => {
        const socket = net.connect(socketPath)
        let buffer = ''
        const timer = setTimeout(() => {
            socket.destroy()
            reject(new Error(`timeout waiting for ${request.method}`))
        }, timeoutMs)
        socket.on('connect', () => {
            socket.write(`${JSON.stringify({ id: 'test', ...request })}\n`)
        })
        socket.on('data', (chunk) => {
            buffer += chunk
            const newline = buffer.indexOf('\n')
            if (newline < 0) return
            clearTimeout(timer)
            socket.destroy()
            try {
                resolve(JSON.parse(buffer.slice(0, newline)))
            } catch (error) {
                reject(error)
            }
        })
        socket.on('error', (error) => {
            clearTimeout(timer)
            reject(error)
        })
    })
}

async function startBridge(controller, paths, overrides = {}) {
    const bridge = new LookitBridge({
        sessionController: controller,
        socketPath: paths.socket,
        discoveryPath: paths.discovery,
        logPath: paths.log,
        defaultCwd: paths.root,
        requestTimeoutMs: 1000,
        promptTimeoutMs: 2000,
        ...overrides,
    })
    await bridge.start()
    return bridge
}

test('hello advertises the protocol and methods', async () => {
    const paths = await workspace()
    const { controller } = fakeController()
    const bridge = await startBridge(controller, paths)
    try {
        const response = await call(paths.socket, { method: 'hello' })
        assert.equal(response.ok, true)
        assert.equal(response.result.protocol, PROTOCOL)
        assert.deepEqual(response.result.methods, ['hello', 'ping', 'list', 'send', 'reveal'])
    } finally {
        await bridge.stop()
    }
})

test('start publishes a readable discovery file and listens on the socket', async () => {
    const paths = await workspace()
    const { controller } = fakeController()
    const bridge = await startBridge(controller, paths)
    try {
        const discovery = JSON.parse(await fs.readFile(paths.discovery, 'utf8'))
        assert.equal(discovery.protocol, PROTOCOL)
        assert.equal(discovery.socket, paths.socket)
        assert.equal(discovery.pid, process.pid)
        const stat = await fs.stat(paths.socket)
        assert.equal(stat.mode & 0o777, 0o600)
    } finally {
        await bridge.stop()
    }
})

test('list normalizes, filters subagents, and sorts by last prompt', async () => {
    const paths = await workspace()
    const { controller } = fakeController([
        summary('older', 'Older task', 100),
        summary('newer', 'Newer task', 300),
        summary('subagent', 'Child', 500, { parentSessionId: 'newer', origin: 'subagent' }),
        { sessionId: 'untitled', updatedAt: 50, cwd: tmpdir(), projections: { values: { sessionListMetadata: { lastPromptAt: null } } } },
    ])
    const bridge = await startBridge(controller, paths)
    try {
        const response = await call(paths.socket, { method: 'list' })
        assert.equal(response.ok, true)
        assert.deepEqual(response.result.items.map((item) => item.sessionId), ['newer', 'older', 'untitled'])
        assert.equal(response.result.items[2].title, 'New session')
        assert.equal(response.result.items[0].lastPromptAt, 300)
        assert.equal(response.result.items[1].running, false)
    } finally {
        await bridge.stop()
    }
})

test('list accepts the Host { items } response shape', async () => {
    const paths = await workspace()
    const controller = {
        async list() {
            return { items: [summary('wrapped', 'Wrapped session', 200)] }
        },
        async create() { return { sessionId: 'unused' } },
        async prompt() { return { accepted: true } },
    }
    const bridge = await startBridge(controller, paths)
    try {
        const response = await call(paths.socket, { method: 'list' })
        assert.equal(response.ok, true)
        assert.deepEqual(response.result.items.map((item) => item.sessionId), ['wrapped'])
        assert.equal(response.result.items[0].title, 'Wrapped session')
    } finally {
        await bridge.stop()
    }
})

test('send recent picks the most recently used session and preserves text then image', async () => {
    const paths = await workspace()
    const { controller, calls } = fakeController([
        summary('older', 'Older', 100),
        summary('recent', 'The recent one', 900),
    ])
    const bridge = await startBridge(controller, paths)
    try {
        const image = Buffer.from('not really a png but base64-valid').toString('base64')
        const response = await call(paths.socket, {
            method: 'send',
            params: {
                target: 'recent',
                text: 'Look at this',
                imageBase64: image,
                imageMediaType: 'image/png',
                imageName: 'shot.png',
            },
        })
        assert.equal(response.ok, true)
        assert.deepEqual(response.result, {
            sessionId: 'recent',
            title: 'The recent one',
            opened: false,
            created: false,
            target: 'recent',
        })
        assert.equal(calls.created.length, 0)
        assert.equal(calls.prompted.length, 1)
        const prompt = calls.prompted[0]
        assert.equal(prompt.sessionId, 'recent')
        assert.equal(prompt.mode, 'queue')
        assert.equal(prompt.content[0].type, 'text')
        assert.equal(prompt.content[0].text, 'Look at this')
        assert.equal(prompt.content[1].type, 'image')
        assert.equal(prompt.content[1].mediaType, 'image/png')
        assert.equal(prompt.content[1].name, 'shot.png')
        assert.equal(prompt.content[1].data, image)
        assert.match(prompt.requestId, /^[0-9a-f-]{36}$/)
    } finally {
        await bridge.stop()
    }
})

test('send new creates in the most recent cwd and sends only the image when text is blank', async () => {
    const paths = await workspace()
    const { controller, calls } = fakeController([
        summary('recent', 'Recent', 500, { cwd: paths.root }),
    ])
    const bridge = await startBridge(controller, paths)
    try {
        const image = Buffer.from('image bytes').toString('base64')
        const response = await call(paths.socket, {
            method: 'send',
            params: {
                target: 'new',
                text: '   ',
                imageBase64: image,
                imageMediaType: 'image/png',
            },
        })
        assert.equal(response.ok, true)
        assert.equal(response.result.created, true)
        assert.equal(response.result.target, 'new')
        assert.equal(response.result.sessionId, 'created-1')
        assert.equal(calls.created.length, 1)
        assert.equal(calls.created[0].cwd, paths.root)
        assert.equal(calls.prompted[0].content.length, 1)
        assert.equal(calls.prompted[0].content[0].type, 'image')
    } finally {
        await bridge.stop()
    }
})

test('send to an explicit session does not list or create', async () => {
    const paths = await workspace()
    const { controller, calls } = fakeController([summary('other', 'Other', 100)])
    const bridge = await startBridge(controller, paths)
    try {
        const response = await call(paths.socket, {
            method: 'send',
            params: {
                sessionId: 'chosen',
                text: 'go here',
                imageBase64: Buffer.from('x').toString('base64'),
                imageMediaType: 'image/png',
            },
        })
        assert.equal(response.ok, true)
        assert.equal(response.result.sessionId, 'chosen')
        assert.equal(response.result.target, 'session')
        assert.equal(calls.list, 0)
        assert.equal(calls.created.length, 0)
        assert.equal(calls.prompted[0].sessionId, 'chosen')
    } finally {
        await bridge.stop()
    }
})

test('send creates when there is no recent session', async () => {
    const paths = await workspace()
    const { controller, calls } = fakeController([])
    const bridge = await startBridge(controller, paths)
    try {
        const response = await call(paths.socket, {
            method: 'send',
            params: {
                target: 'recent',
                text: 'first',
                imageBase64: Buffer.from('x').toString('base64'),
            },
        })
        assert.equal(response.ok, true)
        assert.equal(response.result.created, true)
        assert.equal(response.result.target, 'new')
        assert.equal(calls.created.length, 1)
        assert.equal(calls.prompted[0].sessionId, 'created-1')
    } finally {
        await bridge.stop()
    }
})

test('rejects empty content and unsupported media types with named codes', async () => {
    const paths = await workspace()
    const { controller } = fakeController()
    const bridge = await startBridge(controller, paths)
    try {
        const empty = await call(paths.socket, {
            method: 'send',
            params: { target: 'new', text: '   ' },
        })
        assert.equal(empty.ok, false)
        assert.equal(empty.error.code, 'bad_request')

        const unsupported = await call(paths.socket, {
            method: 'send',
            params: {
                text: 'x',
                imageBase64: Buffer.from('x').toString('base64'),
                imageMediaType: 'image/tiff',
            },
        })
        assert.equal(unsupported.ok, false)
        assert.equal(unsupported.error.code, 'unsupported_media_type')
    } finally {
        await bridge.stop()
    }
})

test('maps a RemoteError-like prompt failure to its code', async () => {
    const paths = await workspace()
    const failure = new Error('Model does not support image input.')
    failure.code = 'session/attachment-invalid'
    const { controller } = fakeController([summary('recent', 'Recent', 100)], { promptError: failure })
    const bridge = await startBridge(controller, paths)
    try {
        const response = await call(paths.socket, {
            method: 'send',
            params: {
                target: 'recent',
                text: 'x',
                imageBase64: Buffer.from('x').toString('base64'),
            },
        })
        assert.equal(response.ok, false)
        assert.equal(response.error.code, 'session/attachment-invalid')
        assert.match(response.error.message, /does not support/)
    } finally {
        await bridge.stop()
    }
})

test('stop removes the socket and own discovery file', async () => {
    const paths = await workspace()
    const { controller } = fakeController()
    const bridge = await startBridge(controller, paths)
    await bridge.stop()
    await assert.rejects(fs.stat(paths.socket))
    await assert.rejects(fs.stat(paths.discovery))
})

test('start is idempotent and a second stop is harmless', async () => {
    const paths = await workspace()
    const { controller } = fakeController()
    const bridge = await startBridge(controller, paths)
    await bridge.start()
    await bridge.stop()
    await bridge.stop()
})

test('apply mounts and unmounts the bridge through ctx.effect', async () => {
    const paths = await workspace()
    const { controller } = fakeController([summary('recent', 'Recent', 100)])
    const cleanups = []
    const ctx = {
        sessionController: controller,
        workspaceRegistry: { list: () => [] },
        webServer: { register: () => () => {} },
        logger: { warn() {} },
        effect(fn) {
            cleanups.push(fn())
        },
    }
    const { apply } = await import('../lib/index.js')
    apply(ctx, {
        enabled: true,
        socketPath: paths.socket,
        discoveryPath: paths.discovery,
        logPath: paths.log,
        defaultCwd: paths.root,
        requestTimeoutMs: 1000,
        promptTimeoutMs: 2000,
        socketTimeoutMs: 5000,
        maxImageBytes: 1024 * 1024,
        maxTextChars: 1000,
        maxLineBytes: 2 * 1024 * 1024,
    })
    await new Promise((resolve) => setTimeout(resolve, 50))
    const response = await call(paths.socket, { method: 'hello' })
    assert.equal(response.ok, true)
    await cleanups[0]()
    await assert.rejects(fs.stat(paths.socket))
})

test('new capture joins the matching DSH workspace and reveals exactly the accepted session', async () => {
    const paths = await workspace()
    const { controller, calls } = fakeController([summary('recent', 'Recent', 100, { cwd: paths.root })])
    const revealed = []
    const bridge = await startBridge(controller, paths, {
        workspaceRegistry: { list: () => [{ id: 'workspace-1', path: paths.root }] },
        reveal: async id => { assert.equal(calls.prompted.length, 1); revealed.push(id); return true },
    })
    try {
        const response = await call(paths.socket, { method: 'send', params: { target: 'new', text: 'hello', openAfterSend: true } })
        assert.equal(response.ok, true)
        assert.deepEqual(calls.created, [{ workspaceId: 'workspace-1' }])
        assert.deepEqual(revealed, [response.result.sessionId])
        assert.equal(response.result.opened, true)
    } finally { await bridge.stop() }
})

test('failed navigation preserves successful delivery and does not submit twice', async () => {
    const paths = await workspace()
    const { controller, calls } = fakeController([summary('recent', 'Recent', 100)])
    const bridge = await startBridge(controller, paths, { reveal: async () => { throw new Error('UI unavailable') } })
    try {
        const response = await call(paths.socket, { method: 'send', params: { text: 'hello', openAfterSend: true } })
        assert.equal(response.ok, true)
        assert.equal(response.result.opened, false)
        assert.equal(calls.prompted.length, 1)
    } finally { await bridge.stop() }
})

test('open-after-send off does not navigate; rejected prompt does not navigate', async () => {
    for (const reject of [false, true]) {
        const paths = await workspace()
        const { controller } = fakeController([summary('recent', 'Recent', 100)], { promptError: reject ? new Error('rejected') : undefined })
        let navigated = false
        const bridge = await startBridge(controller, paths, { reveal: async () => { navigated = true; return true } })
        try {
            const response = await call(paths.socket, { method: 'send', params: { text: 'hello', openAfterSend: reject } })
            assert.equal(response.ok, !reject)
            assert.equal(navigated, false)
        } finally { await bridge.stop() }
    }
})
