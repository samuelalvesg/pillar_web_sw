// Arquivo: mock_env.js
// Módulo: pillar_web_sw / testes JS
// Descrição: Mocks of the service worker globals (caches, fetch, clients,
//   self) over Node's own Request/Response, serving a build dir from disk.
// Dependências: Node 18+ (global Request, Response, Headers, crypto).
// Premissas: each Env is isolated; caches may be shared between Envs to
//   simulate two workers of the same origin.
// Edge Cases: Response.type is overridden per instance (cors/opaque).
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ORIGIN = 'https://app.test';

function withType(response, type) {
  Object.defineProperty(response, 'type', { value: type });
  const clone = response.clone.bind(response);
  response.clone = () => withType(clone(), type);
  return response;
}

function respond(body, { status = 200, type = 'basic' } = {}) {
  return withType(new Response(body, { status }), type);
}

const keyOf = (k) => (typeof k === 'string' ? k : k.url);
const strip = (u) => u.split('?')[0];

class MockCache {
  constructor() { this.map = new Map(); }
  async match(req, opts = {}) {
    const k = keyOf(req);
    for (const [key, res] of this.map) {
      if (key === k || (opts.ignoreSearch && strip(key) === strip(k))) {
        return res.clone();
      }
    }
    return undefined;
  }
  async put(req, res) { this.map.set(keyOf(req), res); }
  async delete(req) { return this.map.delete(keyOf(req)); }
  async keys() { return [...this.map.keys()].map((url) => ({ url })); }
}

class MockCaches {
  constructor() { this.stores = new Map(); this.deleted = []; }
  async open(name) {
    if (!this.stores.has(name)) this.stores.set(name, new MockCache());
    return this.stores.get(name);
  }
  async has(name) { return this.stores.has(name); }
  async delete(name) { this.deleted.push(name); return this.stores.delete(name); }
  async keys() { return [...this.stores.keys()]; }
}

// Static files of a build dir plus per-test overrides and failures.
class MockServer {
  constructor(buildDir) {
    this.buildDir = buildDir;
    this.overrides = new Map();
    this.offline = false;
    this.hang = false;
    this.log = [];
  }
  async fetch(input, init = {}) {
    const url = typeof input === 'string' ? input : input.url;
    this.log.push({ url, cache: init.cache || input.cache });
    if (this.offline) throw new TypeError('offline');
    if (this.hang) return new Promise(() => {});
    const u = new URL(url);
    if (this.overrides.has(u.pathname)) return this.overrides.get(u.pathname)();
    if (u.origin !== ORIGIN) return respond('x', { type: 'cors' });
    const rel = decodeURIComponent(u.pathname.slice(1));
    const file = path.join(this.buildDir, rel === '' ? 'index.html' : rel);
    if (rel.endsWith('/') || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
      if (u.pathname.startsWith('/assets/') || u.pathname.startsWith('/icons/')) {
        return respond('nf', { status: 404 });
      }
      if (rel.includes('.')) return respond('nf', { status: 404 });
      return respond(fs.readFileSync(path.join(this.buildDir, 'index.html')));
    }
    return respond(fs.readFileSync(file));
  }
}

// Boots a worker script in a fresh vm context.
function boot(code, { buildDir, caches = new MockCaches(), active = null }) {
  const listeners = {};
  const server = new MockServer(buildDir);
  const calls = { skipWaiting: 0, claim: 0, unregister: 0, posted: [] };
  const self = {
    addEventListener: (type, fn) => { listeners[type] = fn; },
    registration: {
      scope: ORIGIN + '/',
      active,
      unregister: async () => { calls.unregister++; return true; },
    },
    clients: { claim: async () => { calls.claim++; } },
    skipWaiting: () => { calls.skipWaiting++; },
  };
  const timers = [];
  const context = vm.createContext({
    self, caches, URL, Request, Response, Headers, console: { error() {}, warn() {} },
    crypto: globalThis.crypto,
    fetch: (i, n) => server.fetch(i, n),
    setTimeout: (fn) => { timers.push(fn); return timers.length; },
  });
  vm.runInContext(code, context);

  async function run(type, extra = {}) {
    const pending = [];
    const event = { waitUntil: (p) => pending.push(p), ...extra };
    listeners[type](event);
    await Promise.all(pending);
    return event;
  }

  async function doFetch(url, { method = 'GET', mode = 'no-cors', headers = {} } = {}) {
    const request = {
      url: url.startsWith('http') ? url : ORIGIN + url,
      method, mode, headers: new Headers(headers),
    };
    const event = {
      request,
      responded: false,
      respondWith(p) { this.responded = true; this.promise = p; },
      pending: [],
      waitUntil(p) { this.pending.push(p); },
    };
    listeners.fetch(event);
    if (!event.responded) return { intercepted: false };
    try {
      const response = await event.promise;
      await Promise.all(event.pending);
      return { intercepted: true, response, text: await response.clone().text() };
    } catch (error) {
      return { intercepted: true, error };
    }
  }

  return {
    server, caches, calls, listeners, timers, doFetch,
    install: () => run('install'),
    activate: () => run('activate'),
    message: (data) => {
      const sent = [];
      const port = { postMessage: (m) => sent.push(m) };
      return run('message', { data, ports: [port] }).then(() => sent);
    },
  };
}

module.exports = { boot, MockCaches, respond, ORIGIN };
