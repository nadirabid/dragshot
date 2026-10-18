import test from 'node:test'
import assert from 'node:assert/strict'
import { createServer } from 'node:http'
import { readFile } from 'node:fs/promises'
import vm from 'node:vm'
import { Navigation } from '../lib/navigation.js'

test('real HTTP channel plus shipped client refreshes and selects before acknowledging', async () => {
    const navigation = new Navigation(2000)
    const server = createServer((req, res) => navigation.handle(req, res))
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve))
    const url = `http://127.0.0.1:${server.address().port}`
    const order = []; let selected; let cleanup; let plugin
    const sandbox = { window: { __ModuleLoader__: { load: p => { plugin = p.factory() } } },
        fetch: (_, opts) => fetch(url, opts), AbortController, setTimeout, clearTimeout }
    vm.runInNewContext(await readFile(new URL('../lib/client.js', import.meta.url), 'utf8'), sandbox)
    const result = navigation.reveal('accepted-session')
    plugin.apply({ effect: fn => { cleanup = fn() }, logger: { warn: e => assert.fail(e) },
        sessions: { refresh: async () => order.push('refresh'), refreshProjections: async id => order.push(id) },
        uiWorkspace: { openSession: id => { selected = id; order.push('open') }, selection: { getSnapshot: () => ({ sessionId: selected }) } } })
    try {
        assert.equal(await result, true)
        assert.deepEqual(order, ['refresh', 'accepted-session', 'open'])
        assert.equal(navigation.pending, null)
    } finally { cleanup(); server.closeAllConnections(); await new Promise(resolve => server.close(resolve)) }
})

test('missing client times out, stale acknowledgements cannot claim another capture', async () => {
    const navigation = new Navigation(20)
    const first = navigation.reveal('first')
    const old = navigation.pending.id
    const second = navigation.reveal('second')
    assert.equal(await first, false)
    assert.notEqual(navigation.pending.id, old)
    assert.equal(await second, false)
    assert.equal(navigation.pending, null)
})

test('HTTP acknowledgement for an older capture cannot mark the new capture opened', async () => {
    const navigation = new Navigation(1000)
    const server = createServer((req, res) => navigation.handle(req, res))
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve))
    const url = `http://127.0.0.1:${server.address().port}`
    try {
        const first = navigation.reveal('first')
        const stale = await (await fetch(url)).json()
        const second = navigation.reveal('second')
        assert.equal(await first, false)
        await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ ...stale, opened: true }) })
        assert.equal(navigation.pending.sessionId, 'second')
        const current = await (await fetch(url)).json()
        await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ ...current, opened: true }) })
        assert.equal(await second, true)
        assert.equal(await (await fetch(url)).json(), null)
    } finally { navigation.cancel(); server.closeAllConnections(); await new Promise(resolve => server.close(resolve)) }
})

test('client cannot claim success when selecting a different session', async () => {
    let plugin; let cleanup; let acknowledgement
    const sandbox = { window: { __ModuleLoader__: { load: p => { plugin = p.factory() } } },
        fetch: async (_, options) => {
            if (options.method === 'POST') acknowledgement = JSON.parse(options.body)
            return { ok: true, json: async () => ({ id: 'request', sessionId: 'target' }) }
        }, AbortController, setTimeout, clearTimeout }
    vm.runInNewContext(await readFile(new URL('../lib/client.js', import.meta.url), 'utf8'), sandbox)
    plugin.apply({ effect: fn => { cleanup = fn() },
        sessions: { refresh: async () => {}, refreshProjections: async () => {} },
        uiWorkspace: { openSession: () => {}, selection: { getSnapshot: () => ({ sessionId: 'old-chat' }) } } })
    try {
        await new Promise(resolve => setImmediate(resolve))
        assert.equal(acknowledgement.opened, false)
    } finally { cleanup() }
})
