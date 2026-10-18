/**
 * dsh-lookit — a local capture bridge for the DSH desktop host.
 *
 * Lookit (the menu bar capture app) writes a screenshot and note to a Unix
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
import { LookitBridge } from './bridge.js'
import { Navigation } from './navigation.js'

export const name = 'lookit'

/** The live Session Controller is the whole reason this is a host plugin. */
export const inject = ['sessionController', 'workspaceRegistry', 'webServer']

const SUPPORT = join(homedir(), 'Library', 'Application Support', 'Lookit')

// No runtime npm dependencies: this payload is copied into Application Support.
// Defaults are resolved here so a clean desktop install needs no npm cache.
const defaults = {
    enabled: true,
    socketPath: join(SUPPORT, 'dsh.sock'),
    discoveryPath: join(SUPPORT, 'dsh-bridge.json'),
    logPath: join(homedir(), 'Library', 'Logs', 'LookitDshBridge.log'),
    defaultCwd: homedir(),
    requestTimeoutMs: 15_000,
    promptTimeoutMs: 60_000,
    socketTimeoutMs: 120_000,
    maxImageBytes: 20 * 1024 * 1024,
    maxTextChars: 20_000,
    maxLineBytes: 40 * 1024 * 1024,
}

/**
 * @param ctx - Host Cordis context.
 * @param config - validated plugin configuration.
 */
export function apply(ctx, config = {}) {
    config = { ...defaults, ...config }
    if (!config.enabled) return

    const navigation = new Navigation()
    const bridge = new LookitBridge({
        workspaceRegistry: ctx.workspaceRegistry,
        reveal: id => navigation.reveal(id),
        navigationReady: () => navigation.ready,
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
        const disposeRoute = ctx.webServer.register({ kind: 'exact', path: '/lookit/navigation',
            handler: (req, res) => navigation.handle(req, res) })
        const ready = bridge.start().catch((error) => {
            ctx.logger?.warn?.(`lookit: bridge failed to start: ${error instanceof Error ? error.message : String(error)}`)
        })
        return async () => {
            navigation.cancel()
            disposeRoute()
            await ready
            await bridge.stop()
        }
    }, 'lookit.bridge')
}
