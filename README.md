# pillar_web_sw

A release-scoped service worker for Flutter web builds. Run one command after `flutter build web` and the app can open offline, with its own cache for each release and a kill switch to pull a bad release back.

The generator builds the service worker from the files of each build. Every release gets its own cache, and a failed install leaves the version your users already have untouched.

> Status: alpha. The generator, the worker template, the registration script and the kill switch work and are tested. The API may still change before 0.1.0.

## Why

- Each release has its own cache, named `<prefix>-core-<release_id>`. The release id is a hash of every core file, so a new build never shares a cache with the old one.
- The worker downloads and checks everything into a temporary cache and copies it to the final name only when all of it is good. If anything fails, it deletes the temporary cache and the active worker keeps serving its own.
- Navigation tries the network for three seconds, then falls back to the release's `index.html`, so the app works offline by default.
- `--kill-switch` writes a worker that deletes its caches and unregisters itself.
- It is a Dart command and needs no Node or build tool. Node is only used by the optional JavaScript tests.

## Quick start

Add it to `pubspec.yaml`:

```yaml
dev_dependencies:
  pillar_web_sw:
    git:
      url: https://github.com/samuelalvesg/pillar_web_sw.git
      ref: v0.1.0-alpha.3
```

Build, then generate:

```bash
flutter build web
dart run pillar_web_sw:generate build/web
```

Register the worker in `web/index.html`:

```html
<script src="app-sw-register.js" defer></script>
```

The generator writes two files into `build/web`: `app-service-worker.js` (the file table and the release id are inside it) and `app-sw-register.js`. Run it after the last step that touches the build.

## Configuration

Everything is optional. Without a `web_sw.yaml` every file goes into the core cache.

```yaml
cachePrefix: myapp                 # prefix for the caches
core: ["**"]                       # pre-cached with the release
onDemand: ["assets/books/**"]      # cached the first time they are used
ignore: ["**/*.txt"]               # never cached
neverIntercept: [/api/, /auth/]    # prefixes the worker does not touch
noHashCheck: ["assets/img/**"]     # check the status only, not the hash
navigationFallback: true           # offline navigation gets the release's index.html
```

`ignore` beats `onDemand`, which beats `core`. A file that matches none of them is ignored.

### Local CanvasKit

A build with local CanvasKit (`--no-web-resources-cdn`) puts about 20 MB of variants under `canvaskit/`. Keep in the core only what the loader asks for:

```yaml
core: ["**"]
onDemand: ["canvaskit/chromium/**", "canvaskit/skwasm_heavy.*"]
ignore: ["canvaskit/wimp*", "canvaskit/webparagraph/**"]
```

## How it behaves

| Request | Strategy |
|---|---|
| Navigation | Network first with a 3 s limit, then the release's `index.html` |
| Core files | Release cache first |
| On-demand files | Cached on first use, in `<prefix>-ondemand` |
| `config.js` | Network first, cache as a fallback |
| Fonts and CanvasKit from the CDN | Stale-while-revalidate, up to 60 entries |
| Non-GET, `Range`, other origins, `neverIntercept` | Not touched |

Install checks every core file for status 200. Code and binaries (`.js`, `.mjs`, `.wasm`, fonts, images) are also checked against their hash. Text files (`.html`, `.css`, `.json`, `.svg`, `.xml`, `.txt`) only need status 200, because proxies such as Cloudflare rewrite HTML at the edge and no content hash survives that. Force the status-only check on other files with `noHashCheck`.

The worker does not call `skipWaiting` on its own. When a new release is waiting, `app-sw-register.js` fires an `app-sw-update-available` event on `window`. The text and place of the "new version" notice are yours:

```js
window.addEventListener('app-sw-update-available', (e) => {
  // show your own prompt, then:
  e.detail.registration.waiting.postMessage({ type: 'app-sw-skip-waiting' });
});
navigator.serviceWorker.addEventListener('controllerchange', () => location.reload());
```

Ask the worker for its state with `{type: 'app-sw-status'}`; it answers `{releaseId, state, lastInstallError, configPrefetchError}`.

## Command reference

```bash
dart run pillar_web_sw:generate <build/web> [--config web_sw.yaml] [--release-id <id>] [--check-only] [--print-table] [--kill-switch]
```

| Flag | What it does |
|---|---|
| `--config` | Path to `web_sw.yaml`. Defaults to `./web_sw.yaml` when it exists. |
| `--release-id` | Use this id instead of the computed one. |
| `--check-only` | Only compare `precache_manifest.json` with the disk. |
| `--print-table` | Print the file table (core, on-demand, ignored) as stable JSON. |
| `--kill-switch` | Write a worker that deletes the caches and unregisters. Publish it to pull back a bad release, then run the normal generator. |

Exit codes: `0` ok, `1` the manifest does not match the disk, `2` bad usage (arguments, directory or configuration).

## Tests

```bash
dart test
```

The worker tests run in Node against mocks of `caches`, `fetch` and `self`. Without Node on the PATH they are skipped with a "JS NOT EXECUTED" message and only the Dart tests run.

## License

MIT
