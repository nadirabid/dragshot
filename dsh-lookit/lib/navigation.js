import { randomUUID } from 'node:crypto'

// A short-lived request, acknowledged only after the client selects the chat.
// Requests are never replayed after a timeout or on a later app launch.
export class Navigation {
    pending = null
    lastPoll = 0
    get ready() { return Date.now() - this.lastPoll < 6000 }
    constructor(timeoutMs = 8000) { this.timeoutMs = timeoutMs }
    reveal(sessionId) {
        this.cancel()
        return new Promise(resolve => {
            const timer = setTimeout(() => this.cancel(), this.timeoutMs)
            this.pending = { id: randomUUID(), sessionId, finish: opened => {
                clearTimeout(timer)
                this.pending = null
                resolve(opened)
            } }
        })
    }
    cancel() { this.pending?.finish(false) }
    handle(req, res) {
        res.setHeader('Cache-Control', 'no-store')
        res.setHeader('Content-Type', 'application/json')
        if (req.method === 'GET') {
            this.lastPoll = Date.now()
            const p = this.pending
            res.end(JSON.stringify(p ? { id: p.id, sessionId: p.sessionId } : null))
        } else if (req.method === 'POST' && req.headers['content-type'] === 'application/json') {
            let body = ''
            req.on('data', chunk => { body += chunk; if (body.length > 1024) req.destroy() })
            req.on('end', () => {
                try {
                    const ack = JSON.parse(body)
                    if (ack.id === this.pending?.id && ack.sessionId === this.pending?.sessionId) {
                        this.pending.finish(ack.opened === true)
                    }
                    res.end('{}')
                } catch { res.writeHead(400); res.end('{}') }
            })
        } else { res.writeHead(405); res.end('{}') }
    }
}
