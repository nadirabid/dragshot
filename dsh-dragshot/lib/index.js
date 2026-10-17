/**
 * dsh-dragshot — a local capture bridge for the DSH desktop host.
 *
 * DragShot (the menu bar capture app) writes a screenshot and note to a Unix
 * socket. This plugin turns that into a real DSH session: it sends to a chosen
 * session, the most recently used session, or a new one in the most recent
 * session's directory (or the configured default).
 *
 * Why a plugin: the running desktop host owns the live sessions. A separate
 * ACP process can list and resume persisted sessions, but it cannot attach to a
 * session the desktop app currently holds. A host plugin can call the same
 * `sessionController` the UI uses.
 *
 * The bridge exposes only session summaries (title, cwd, activity) and the
 * send operation. It never exposes conversation history, and it never logs the
 * note or the screenshot.
 */

import { homedir } from 'node:os'
import { join } from 'node:path'
import z from '@deepseek-ai/schemastery'
import { DragShotBridge } from './bridge.js'

export const name = 'dragshot'

/** The live Session Controller is the whole reason this is a host plugin. */
export const inject = ['sessionController']

const SUPPORT = join(homedir(), 'Library', 'Application Support', 'DragShot')

export const Config = z.object({
    /** Mount or disable the bridge without removing the row. */
    enabled: z.boolean().default(true),
    /** Unix socket the DragShot app connects to. */
    socketPath: z.string().default(join(SUPPORT, 'dsh.sock')),
    /** Discovery file read by DragShot; contains the socket path and protocol version. */
    discoveryPath: z.string().default(join(SUPPORT, 'dsh-bridge.json')),
    /** Diagnostics only. Contains method names and session ids, never note text or image bytes. */
    logPath: z.string().default(join(homedir(), 'Library', 'Logs', 'DragShotDshBridge.log')),
    /** New sessions start here when there is no recent session cwd. */
    defaultCwd: z.string().default(homedir()),
    /** Deadline for the session-list read. */
    requestTimeoutMs: z.number().default(15_000),
    /** Deadline for prompt admission. Generation is not awaited. */
    promptTimeoutMs: z.number().default(60_000),
    /** Idle socket lifetime. */
    socketTimeoutMs: z.number().default(120_000),
    /** Maximum decoded screenshot size. */
    maxImageBytes: z.number().default(20 * 1024 * 1024),
    /** Maximum note length. */
    maxTextChars: z.number().default(20_000),
    /** Maximum request line, including base64 image. */
    maxLineBytes: z.number().default(40 * 1024 * 1024),
})

/**
 * @param ctx - Host Cordis context.
 * @param config - validated plugin configuration.
 */
export function apply(ctx, config) {
    if (!config.enabled) return

    const bridge = new DragShotBridge({
        sessionController: ctx.sessionController,
        socketPath: config.socketPath,
        discoveryPath: config.discoveryPath,
        logPath: config.logPath,
        defaultCwd: config.defaultCwd,
        requestTimeoutMs: config.requestTimeoutMs,
        promptTimeoutMs: config.promptTimeoutMs,
        socketTimeoutMs: config.socketTimeoutMs,
        maxImageBytes: config.maxImageBytes,
        maxTextChars: config.maxTextChars,
        maxLineBytes: config.maxLineBytes,
        logger: ctx.logger,
    })

    ctx.effect(() => {
        const ready = bridge.start().catch((error) => {
            ctx.logger?.warn?.(`dragshot: bridge failed to start: ${error instanceof Error ? error.message : String(error)}`)
        })
        return async () => {
            await ready
            await bridge.stop()
        }
    }, 'dragshot.bridge')
}
