import test from 'node:test'
import assert from 'node:assert/strict'
import { mkdtemp, mkdir, cp, rm, realpath, readFile, writeFile, access } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { execFileSync } from 'node:child_process'

async function fixture(fn) {
    const root = await mkdtemp(join(tmpdir(), 'lookit-install-'))
    try {
        const home = join(root, 'home'), source = join(root, 'checkout with spaces')
        const profile = join(home, '.dsh/profiles/desktop')
        const support = join(home, 'Library/Application Support/Lookit')
        await mkdir(profile, { recursive: true })
        await mkdir(source)
        for (const name of ['lib', 'package.json', 'install.sh']) {
            await cp(new URL(`../${name}`, import.meta.url), join(source, name), { recursive: true })
        }
        const env = { ...process.env, HOME: home, DSH_HOME: join(home, '.dsh'), DSH_PROFILE: 'desktop', LOOKIT_SUPPORT_DIR: support }
        const install = (path = source) => execFileSync('bash', [join(path, 'install.sh'), root], { env })
        await fn({ root, home, source, profile, support, env, install })
    } finally { await rm(root, { recursive: true, force: true }) }
}

test('clean install needs no npm dependencies and remains loadable after checkout deletion', async () => fixture(async f => {
    f.install()
    const target = await realpath(join(f.home, '.dsh/profiles/node_modules/dsh-lookit'))
    assert.equal(target, await realpath(join(f.support, 'Integrations/dsh-lookit')))
    await rm(f.source, { recursive: true })
    execFileSync(process.execPath, ['--input-type=module', '-e', `import(${JSON.stringify(join(target, 'lib/index.js'))})`])
    await access(join(target, 'lib/client.js'))
    await assert.rejects(access(join(target, 'node_modules')))
}))

test('upgrades and moved checkouts preserve profile configuration without duplicate rows', async () => fixture(async f => {
    const patch = join(f.profile, 'cordis.patch.yml')
    await writeFile(patch, '# unrelated configuration\n- id: other\n  config:\n    enabled: false\n')
    f.install()
    let text = await readFile(patch, 'utf8')
    text = text.replace('enabled: true', 'enabled: false').replace(/defaultCwd: .*/, 'defaultCwd: "/saved/workspace"')
    await writeFile(patch, text)
    const moved = join(f.root, 'moved checkout')
    await cp(f.source, moved, { recursive: true })
    await rm(f.source, { recursive: true })
    f.install(moved)
    assert.equal(await readFile(patch, 'utf8'), text)
    assert.equal((text.match(/id: lookit-bridge/g) ?? []).length, 1)
}))

test('legacy managed row and single-root watcher migrate without changing user config', async () => fixture(async f => {
    const patch = join(f.profile, 'cordis.patch.yml')
    await writeFile(patch, '- insert:\n    - id: dragshot-bridge\n      name: dsh-dragshot\n      config:\n        enabled: false\n- id: hmr\n  config:\n    root: [ "/old/dsh-dragshot" ]\n')
    f.install()
    const text = await readFile(patch, 'utf8')
    assert.match(text, /id: lookit-bridge/)
    assert.match(text, /name: dsh-lookit/)
    assert.match(text, /enabled: false/)
    assert.ok(text.includes(join(f.support, 'Integrations/dsh-lookit')))
    assert.ok(!text.includes('/old/'))
}))

test('incomplete source cannot replace an existing working payload or profile', async () => fixture(async f => {
    f.install()
    const patch = await readFile(join(f.profile, 'cordis.patch.yml'), 'utf8')
    const installed = join(f.support, 'Integrations/dsh-lookit/lib/client.js')
    const original = await readFile(installed, 'utf8')
    await rm(join(f.source, 'lib/client.js'))
    assert.throws(() => f.install())
    assert.equal(await readFile(installed, 'utf8'), original)
    assert.equal(await readFile(join(f.profile, 'cordis.patch.yml'), 'utf8'), patch)
}))

test('uninitialized profile is not created and unmanaged package directories are not overwritten', async () => fixture(async f => {
    await rm(f.profile, { recursive: true })
    assert.throws(() => f.install())
    await mkdir(f.profile, { recursive: true })
    await mkdir(join(f.home, '.dsh/profiles/node_modules/dsh-lookit'), { recursive: true })
    assert.throws(() => f.install())
}))
