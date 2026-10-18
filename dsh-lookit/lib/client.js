window.__ModuleLoader__.load({
    id: 'dsh-lookit',
    factory: () => ({
        inject: ['uiWorkspace', 'sessions'],
        apply(ctx) {
            ctx.effect(() => {
                let stopped = false
                let timer
                let lastId
                const controller = new AbortController()
                const request = (options = {}) => {
                    const transport = globalThis.__DSH_TRANSPORT__
                    const fetcher = transport?.fetch ? transport.fetch.bind(transport) : globalThis.fetch.bind(globalThis)
                    return fetcher('/lookit/navigation', { ...options, signal: controller.signal })
                }
                const poll = async () => {
                    try {
                        const response = await request()
                        if (!response.ok) throw new Error(`Lookit navigation: ${response.status}`)
                        const pending = await response.json()
                        if (pending && pending.id !== lastId && typeof pending.sessionId === 'string') {
                            lastId = pending.id
                            let opened = false
                            try {
                                await ctx.sessions.refresh()
                                await ctx.sessions.refreshProjections(pending.sessionId)
                                if (stopped) return
                                ctx.uiWorkspace.openSession(pending.sessionId)
                                opened = ctx.uiWorkspace.selection.getSnapshot().sessionId === pending.sessionId
                            } finally {
                                if (!stopped) await request({ method: 'POST', headers: { 'Content-Type': 'application/json' },
                                    body: JSON.stringify({ ...pending, opened }) })
                            }
                        }
                    } catch (error) {
                        if (!stopped) ctx.logger?.warn?.(`Lookit navigation: ${error.message}`)
                    } finally {
                        if (!stopped) timer = setTimeout(poll, 1000)
                    }
                }
                void poll()
                return () => { stopped = true; clearTimeout(timer); controller.abort() }
            }, 'lookit.navigation')
        },
    }),
})
