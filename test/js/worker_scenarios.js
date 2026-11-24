// Arquivo: worker_scenarios.js
// Módulo: pillar_web_sw / testes JS
// Descrição: Runs the generated worker, kill switch and register script in
//   mocks; prints one JSON array of {name, ok, error}.
// Dependências: mock_env.js, Node 18+.
// Premissas: argv = <build dir with the worker> <build dir with the kill
//   switch>; the build has config.js, a hashed core font, an on-demand
//   bible and neverIntercept [/api/].
// Edge Cases: `--list` prints only the scenario names.
'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const { boot, MockCaches, respond, ORIGIN } = require('./mock_env');

const [buildDir, killDir] = process.argv.slice(2).filter((a) => a[0] !== '-');
const workerCode = () => fs.readFileSync(path.join(buildDir, 'app-service-worker.js'), 'utf8');
const table = () => JSON.parse(/const TABLE = (\{[\s\S]*?\n\});/.exec(workerCode())[1]);
const nextRelease = (id) => workerCode().replace(`"releaseId": "${table().releaseId}"`, `"releaseId": "${id}"`);
const CORE = () => `app-core-${table().releaseId}`;
const fresh = (opts = {}) => boot(workerCode(), { buildDir, ...opts });
const installed = async (opts) => { const w = fresh(opts); await w.install(); await w.activate(); return w; };
const hasKey = async (w, cache, url) => Boolean(await (await w.caches.open(cache)).match(ORIGIN + url));
const rejects = async (p, re) => {
  try { await p; } catch (e) { assert.match(String(e.message || e), re); return; }
  assert.fail('expected rejection');
};

const scenarios = {
  async 'install caches the core with cache reload, skipping config.js'() {
    const w = fresh();
    await w.install();
    const core = table().core.filter((e) => e.url !== 'config.js');
    assert.strictEqual((await (await w.caches.open(CORE())).keys()).length, core.length);
    assert.ok(w.server.log.every((l) => l.cache === 'reload'));
    assert.ok(!(await hasKey(w, CORE(), '/config.js')), 'not in the release');
    assert.strictEqual(w.calls.skipWaiting, 0);
  },
  async 'install rejects on a non-200 and leaves the old release alone'() {
    const caches = new MockCaches();
    const old = await installed({ caches });
    const w = boot(nextRelease('newrel01'), { buildDir, caches });
    w.server.overrides.set('/main.dart.js', async () => respond('x', { status: 503 }));
    await rejects(w.install(), /main\.dart\.js: status 503/);
    assert.ok(await caches.has(CORE()));
    assert.ok(!(await caches.has('app-core-newrel01')));
    assert.ok(await hasKey(old, CORE(), '/index.html'));
  },
  async 'HTML that a proxy rewrote installs and is served from the cache'() {
    const w = fresh();
    const rewritten = '<html><a href="/cdn-cgi/content?id=1"></a></html>';
    w.server.overrides.set('/index.html', async () => respond(rewritten));
    await w.install();
    await w.activate();
    w.server.offline = true;
    assert.strictEqual((await w.doFetch('/eventos/1', { mode: 'navigate' })).text, rewritten);
  },
  async 'the table marks text as status-only and code and binaries as hash'() {
    const check = Object.fromEntries(table().core.map((e) => [e.url, e.check]));
    assert.strictEqual(check['index.html'], 'status');
    assert.strictEqual(check['version.json'], 'status');
    assert.strictEqual(check['main.dart.js'], 'hash');
    assert.strictEqual(check['icons/Icon-192.png'], 'hash');
  },
  async 'code and unlisted binaries are still hash-checked next to rewritten HTML'() {
    for (const url of ['/main.dart.js', '/icons/Icon-192.png']) {
      const w = fresh();
      w.server.overrides.set('/index.html', async () => respond('<html>cf</html>'));
      w.server.overrides.set(url, async () => respond('tampered'));
      await rejects(w.install(), /hash .* differs/);
    }
  },
  async 'noHashCheck from the config relaxes the check for that entry only'() {
    assert.strictEqual(
      table().core.find((e) => e.url === 'assets/AssetManifest.bin').check, 'status');
    const w = fresh();
    w.server.overrides.set('/assets/AssetManifest.bin', async () => respond('proxied'));
    await w.install();
    const bad = fresh();
    bad.server.overrides.set('/flutter.js', async () => respond('tampered'));
    await rejects(bad.install(), /hash/);
  },
  async 'install rejects when a hash does not match'() {
    const w = fresh();
    w.server.overrides.set('/flutter.js', async () => respond('tampered'));
    await rejects(w.install(), /flutter\.js: hash .* differs/);
    assert.ok(!(await w.caches.has(CORE())));
  },
  async 'a failed install is reported by status from another instance'() {
    const caches = new MockCaches();
    const bad = boot(nextRelease('newrel02'), { buildDir, caches });
    bad.server.offline = true;
    await rejects(bad.install(), /offline/);
    const reader = boot(nextRelease('newrel02'), { buildDir, caches });
    const [reply] = await reader.message({ type: 'app-sw-status' });
    assert.match(reply.lastInstallError, /offline/);
    assert.strictEqual(reply.releaseId, 'newrel02');
  },
  async 'status answers release id, state and no error when healthy'() {
    const w = await installed();
    const [reply] = await w.message({ type: 'app-sw-status' });
    assert.deepStrictEqual(
      [reply.type, reply.releaseId, reply.state, reply.lastInstallError],
      ['app-sw-status', table().releaseId, 'activated', null],
    );
  },
  async 'skipWaiting only on the app-sw-skip-waiting message'() {
    const w = fresh();
    await w.message({ type: 'other' });
    await w.message({ type: 'symmetris-push-received' });
    assert.strictEqual(w.calls.skipWaiting, 0);
    await w.message({ type: 'app-sw-skip-waiting' });
    assert.strictEqual(w.calls.skipWaiting, 1);
  },
  async 'navigation is network first'() {
    const w = await installed();
    w.server.overrides.set('/', async () => respond('fresh-index'));
    const r = await w.doFetch('/', { mode: 'navigate' });
    assert.strictEqual(r.text, 'fresh-index');
  },
  async 'navigation falls back to this release index.html offline, deep link too'() {
    const w = await installed();
    const html = fs.readFileSync(path.join(buildDir, 'index.html'), 'utf8');
    w.server.offline = true;
    for (const url of ['/', '/eventos/42?x=1']) {
      const r = await w.doFetch(url, { mode: 'navigate' });
      assert.strictEqual(r.text, html);
    }
  },
  async 'navigation falls back after the 3 s timeout and on 5xx'() {
    const w = await installed();
    const html = fs.readFileSync(path.join(buildDir, 'index.html'), 'utf8');
    w.server.hang = true;
    const pending = w.doFetch('/eventos/1', { mode: 'navigate' });
    await new Promise((r) => setImmediate(r));
    w.timers.forEach((t) => t());
    assert.strictEqual((await pending).text, html);
    w.server.hang = false;
    w.server.overrides.set('/', async () => respond('boom', { status: 502 }));
    assert.strictEqual((await w.doFetch('/', { mode: 'navigate' })).text, html);
  },
  async 'navigation to a missing static path is left to the network'() {
    const w = await installed();
    for (const url of ['/assets/nope.png', '/canvaskit/x.wasm', '/icons/x.png', '/main.dart.zzz.js']) {
      assert.strictEqual((await w.doFetch(url, { mode: 'navigate' })).intercepted, false, url);
      assert.strictEqual((await w.doFetch(url)).intercepted, false, url);
    }
  },
  async 'core entries without hash come from the release cache first'() {
    const w = await installed();
    w.server.overrides.set('/flutter_bootstrap.js', async () => respond('NEW'));
    const cached = fs.readFileSync(path.join(buildDir, 'flutter_bootstrap.js'), 'utf8');
    assert.strictEqual((await w.doFetch('/flutter_bootstrap.js?v=2')).text, cached);
    w.server.offline = true;
    assert.strictEqual((await w.doFetch('/main.dart.js')).intercepted, true);
    assert.ok(!(await w.doFetch('/main.dart.js')).error);
  },
  async 'hashed core entries are cache first without revalidating'() {
    const w = await installed();
    const font = table().core.find((e) => e.urlHashed).url;
    const before = w.server.log.length;
    const r = await w.doFetch('/' + font);
    assert.ok(r.response.ok);
    assert.strictEqual(w.server.log.length, before);
  },
  async 'on-demand entries are stored at first use and then served offline'() {
    const w = await installed();
    const url = '/' + table().onDemand[0].url;
    assert.strictEqual((await w.doFetch(url)).response.ok, true);
    w.server.offline = true;
    const again = await w.doFetch(url);
    assert.ok(again.response.ok && !again.error);
    assert.ok(Object.keys(table()).includes('onDemand'));
  },
  async 'config.js is network first with cache fallback'() {
    const w = await installed();
    w.server.overrides.set('/config.js', async () => respond('v1'));
    assert.strictEqual((await w.doFetch('/config.js')).text, 'v1');
    w.server.overrides.set('/config.js', async () => respond('v2'));
    assert.strictEqual((await w.doFetch('/config.js')).text, 'v2');
    w.server.offline = true;
    assert.strictEqual((await w.doFetch('/config.js')).text, 'v2');
    const cold = fresh();
    cold.server.overrides.set('/config.js', async () => respond('nf', { status: 404 }));
    await cold.install();
    await cold.activate();
    cold.server.overrides.clear();
    cold.server.offline = true;
    assert.ok((await cold.doFetch('/config.js')).error);
  },
  async 'CDN fonts use stale-while-revalidate with CORS responses only'() {
    const w = await installed();
    const url = 'https://fonts.gstatic.com/s/roboto.woff2';
    w.server.overrides.set('/s/roboto.woff2', async () => respond('A', { type: 'cors' }));
    assert.strictEqual((await w.doFetch(url)).text, 'A');
    w.server.overrides.set('/s/roboto.woff2', async () => respond('B', { type: 'cors' }));
    assert.strictEqual((await w.doFetch(url)).text, 'A');
    assert.strictEqual((await w.doFetch(url)).text, 'B');
    w.server.overrides.set('/s/opaque.woff2', async () => respond('o', { type: 'opaque' }));
    await w.doFetch('https://fonts.gstatic.com/s/opaque.woff2');
    const runtime = await w.caches.open('app-runtime');
    assert.ok(!(await runtime.match('https://fonts.gstatic.com/s/opaque.woff2')));
    const canvas = 'https://www.gstatic.com/flutter-canvaskit/abc/canvaskit.wasm';
    assert.strictEqual((await w.doFetch(canvas)).intercepted, true);
    assert.strictEqual((await w.doFetch('https://www.gstatic.com/other.js')).intercepted, false);
  },
  async 'the runtime cache is capped'() {
    const w = await installed();
    for (let i = 0; i < 75; i++) {
      await w.doFetch(`https://fonts.gstatic.com/s/f${i}.woff2`);
    }
    const runtime = await w.caches.open('app-runtime');
    assert.strictEqual((await runtime.keys()).length, 60);
  },
  async 'non-GET, Range, other origins and neverIntercept are untouched'() {
    const w = await installed();
    const untouched = [
      w.doFetch('/main.dart.js', { method: 'POST' }),
      w.doFetch('/main.dart.js', { headers: { Range: 'bytes=0-9' } }),
      w.doFetch('https://api.other.test/main.dart.js'),
      w.doFetch('/api/events'),
      w.doFetch('/api/events', { mode: 'navigate' }),
      w.doFetch('/not-in-table.json'),
    ];
    for (const r of await Promise.all(untouched)) assert.strictEqual(r.intercepted, false);
  },
  async 'activate removes other releases, legacy and stale on-demand caches'() {
    const caches = new MockCaches();
    for (const name of ['app-core-old1', 'flutter-app-cache', 'flutter-temp-cache', 'flutter-app-manifest', 'other-core-x']) {
      await caches.open(name);
    }
    const od = await caches.open('app-ondemand');
    await od.put(ORIGIN + '/assets/bible/gone.1.json', respond('x'));
    const w = fresh({ caches, active: {} });
    await w.install();
    const keep = ORIGIN + '/' + table().onDemand[0].url;
    await od.put(keep, respond('k'));
    await w.activate();
    assert.deepStrictEqual(
      (await caches.keys()).sort(),
      [CORE(), 'app-meta', 'app-ondemand', 'app-runtime', 'other-core-x'].sort(),
    );
    assert.deepStrictEqual((await od.keys()).map((k) => k.url), [keep]);
    assert.strictEqual(w.calls.claim, 0, 'previous release exists');
  },
  async 'a new worker with the same core installs without touching the active cache'() {
    const caches = new MockCaches();
    const active = await installed({ caches });
    const before = (await (await caches.open(CORE())).keys()).length;
    caches.deleted.length = 0;
    const other = boot(workerCode() + '\n// other worker model\n', { buildDir, caches, active: {} });
    await other.install();
    assert.ok(!caches.deleted.includes(CORE()), 'active cache was deleted');
    assert.strictEqual((await (await caches.open(CORE())).keys()).length, before);
    assert.ok(!(await caches.has(CORE() + '-installing')));
    active.server.offline = true;
    assert.ok((await active.doFetch('/', { mode: 'navigate' })).response.ok);
  },
  async 'an install that fails midway leaves the active cache intact and usable offline'() {
    const caches = new MockCaches();
    const active = await installed({ caches });
    const before = (await (await caches.open(CORE())).keys()).length;
    caches.deleted.length = 0;
    const other = boot(workerCode() + '\n// other worker model\n', { buildDir, caches, active: {} });
    other.server.overrides.set('/main.dart.js', async () => respond('x', { status: 503 }));
    await rejects(other.install(), /status 503/);
    assert.ok(!caches.deleted.includes(CORE()), 'active cache was deleted');
    assert.strictEqual((await (await caches.open(CORE())).keys()).length, before);
    assert.ok(!(await caches.has(CORE() + '-installing')), 'temp cache left');
    const reopened = boot(workerCode(), { buildDir, caches, active: {} });
    reopened.server.offline = true;
    const html = fs.readFileSync(path.join(buildDir, 'index.html'), 'utf8');
    assert.strictEqual((await reopened.doFetch('/eventos/1', { mode: 'navigate' })).text, html);
    assert.strictEqual((await reopened.doFetch('/main.dart.js')).response.ok, true);
  },
  async 'a successful install promotes the temp cache and activate cleans the old ones'() {
    const caches = new MockCaches();
    await installed({ caches, buildDir });
    const next = boot(nextRelease('newrel04'), { buildDir, caches, active: {} });
    await next.install();
    assert.ok(await caches.has('app-core-newrel04'));
    assert.ok(!(await caches.has('app-core-newrel04-installing')));
    assert.ok(await caches.has(CORE()), 'old release stays until activate');
    await next.activate();
    assert.ok(!(await caches.has(CORE())));
    assert.ok(await caches.has('app-core-newrel04'));
    assert.ok(await hasKey(next, 'app-core-newrel04', '/index.html'));
  },
  async 'claim happens only on the first install, and the mark is cleared'() {
    const caches = new MockCaches();
    const first = await installed({ caches });
    assert.strictEqual(first.calls.claim, 1);
    const meta = await caches.open('app-meta');
    assert.strictEqual((await meta.keys()).length, 0, 'mark cleared');
    const update = boot(nextRelease('newrel03'), { buildDir, caches, active: {} });
    await update.install();
    await update.activate();
    assert.strictEqual(update.calls.claim, 0);
    assert.strictEqual((await meta.keys()).length, 0);
  },
  async 'reinstall after caches were wiped but with an active worker does not claim'() {
    const w = await installed({ active: {} });
    assert.strictEqual(w.calls.claim, 0);
  },
  async 'the first-install mark survives until a later activate'() {
    const caches = new MockCaches();
    const a = fresh({ caches });
    await a.install();
    const b = fresh({ caches });
    await b.activate();
    assert.strictEqual(b.calls.claim, 1);
  },
  async 'install pre-caches config.js in the runtime cache with reload'() {
    const w = fresh();
    w.server.overrides.set('/config.js', async () => respond('tenant-cfg'));
    await w.install();
    assert.ok(w.server.log.some((l) => l.url.endsWith('/config.js') && l.cache === 'reload'));
    await w.activate();
    w.server.offline = true;
    assert.strictEqual((await w.doFetch('/config.js')).text, 'tenant-cfg');
    const [reply] = await w.message({ type: 'app-sw-status' });
    assert.strictEqual(reply.configPrefetchError, null);
  },
  async 'config.js is served offline on reopen after a first online visit'() {
    const caches = new MockCaches();
    const first = fresh({ caches });
    await first.install();
    await first.activate();
    const reopened = fresh({ caches });
    reopened.server.offline = true;
    const onDisk = fs.readFileSync(path.join(buildDir, 'config.js'), 'utf8');
    assert.strictEqual((await reopened.doFetch('/config.js')).text, onDisk);
  },
  async 'install survives config.js failing, 404 or not ok, and reports it'() {
    const failures = [
      async () => { throw new TypeError('boom'); },
      async () => respond('nf', { status: 404 }),
      async () => respond('x', { status: 500 }),
      async () => respond('x', { type: 'opaque' }),
    ];
    for (const failure of failures) {
      const w = fresh();
      w.server.overrides.set('/config.js', failure);
      await w.install();
      await w.activate();
      assert.ok(!(await hasKey(w, 'app-runtime', '/config.js')));
      assert.ok(await hasKey(w, CORE(), '/index.html'));
      const [reply] = await w.message({ type: 'app-sw-status' });
      assert.ok(reply.configPrefetchError);
      assert.strictEqual(reply.lastInstallError, null);
    }
  },
  async 'kill switch wipes app caches and unregisters, nothing else'() {
    const caches = new MockCaches();
    for (const name of ['app-core-a', 'app-ondemand', 'app-runtime', 'flutter-app-cache', 'other-x']) {
      await caches.open(name);
    }
    const code = fs.readFileSync(path.join(killDir, 'app-service-worker.js'), 'utf8');
    const w = boot(code, { buildDir: killDir, caches });
    assert.strictEqual(w.listeners.fetch, undefined);
    await w.install();
    assert.strictEqual(w.calls.skipWaiting, 1);
    await w.activate();
    assert.deepStrictEqual((await caches.keys()).sort(), ['flutter-app-cache', 'other-x']);
    assert.strictEqual(w.calls.unregister, 1);
  },
  async 'register script waits for load and registers with the right options'() {
    const env = registerEnv({ readyState: 'loading' });
    assert.strictEqual(env.registered.length, 0);
    env.fireLoad();
    await tick();
    // JSON compare: the objects were created in another vm realm.
    assert.strictEqual(JSON.stringify(env.registered), JSON.stringify([[
      'https://app.test/app-service-worker.js',
      { scope: 'https://app.test/', updateViaCache: 'none' },
    ]]));
  },
  async 'register script never throws and fires the update event'() {
    registerEnv({ readyState: 'complete', noSupport: true });
    const rejected = registerEnv({ readyState: 'complete', reject: true });
    await tick();
    assert.strictEqual(rejected.registered.length, 1);
    const throwing = registerEnv({ readyState: 'complete', throwSync: true });
    assert.strictEqual(throwing.registered.length, 1);
    const upd = registerEnv({ readyState: 'complete', waiting: true });
    await tick();
    assert.strictEqual(upd.events.length, 1);
    assert.strictEqual(upd.events[0].type, 'app-sw-update-available');
  },
};

const tick = () => new Promise((r) => setImmediate(r));

function registerEnv({ readyState, noSupport, reject, throwSync, waiting }) {
  const code = fs.readFileSync(path.join(buildDir, 'app-sw-register.js'), 'utf8');
  const registered = [];
  const events = [];
  const loads = [];
  const registration = {
    waiting: waiting ? {} : null,
    addEventListener() {},
  };
  const serviceWorker = {
    controller: {},
    register(url, opts) {
      registered.push([url, opts]);
      if (throwSync) throw new Error('sync');
      return reject ? Promise.reject(new Error('no')) : Promise.resolve(registration);
    },
  };
  const window = {
    addEventListener: (t, fn) => loads.push(fn),
    dispatchEvent: (e) => events.push(e),
  };
  vm.runInNewContext(code, {
    navigator: noSupport ? {} : { serviceWorker },
    document: {
      readyState,
      currentScript: { src: ORIGIN + '/app-sw-register.js' },
      baseURI: ORIGIN + '/deep/link',
    },
    window, URL, console: { warn() {} },
    CustomEvent: class { constructor(type, init) { this.type = type; this.detail = init.detail; } },
  });
  return { registered, events, fireLoad: () => loads.forEach((f) => f()) };
}

async function main() {
  if (process.argv.includes('--list')) {
    console.log(JSON.stringify(Object.keys(scenarios)));
    return;
  }
  const results = [];
  for (const [name, fn] of Object.entries(scenarios)) {
    try {
      await fn();
      results.push({ name, ok: true });
    } catch (error) {
      results.push({ name, ok: false, error: String((error && error.stack) || error) });
    }
  }
  console.log(JSON.stringify(results));
}

main();
