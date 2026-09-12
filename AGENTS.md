# AGENTS.md

Directions for any AI agent or new contributor working on **this fork**
(`Asif2BD/gods-eye-view`). Read this before changing anything.

Upstream is `bilawalsidhu/gods-eye-view`. This fork exists to **self-host the app**
at `https://gods-eye.asif.dev`. Keep divergence from upstream minimal so rebasing
stays cheap.

---

## The five things that will bite you

### 1. The live data layers only exist on the Vite **dev server**

The providers in `server/providers/` are Vite **plugins**. Most register only
`configureServer`, which means they exist on the dev server and nowhere else:

| Provider | File | Survives `vite preview`? |
|---|---|---|
| OpenSky aircraft | `server/providers/aircraft/opensky.js` | no |
| adsb.lol military | `server/providers/aircraft/adsb-lol.js` | no |
| CelesTrak satellites | `server/providers/space/celestrak.js` | no |
| CCTV | `server/providers/local.js` | no |
| Overpass roads | `server/providers/local.js` | no |
| NASA FIRMS | `server/providers/firms.js` | no |
| TomTom traffic | `server/providers/traffic.js` | no |
| GBFS bike share | `server/providers/gbfs.js` | no |
| Terrain heights | `server/providers/terrain.js` | no |

**So the container runs `npx vite`, not a production build.** A static build or
`vite preview` serves the globe with most feeds dead. Do not "optimise" this into
a static build — you will silently break the app.

### 2. nginx denies dot-segment paths

xCloud's nginx vhost carries `location ~ /\. { deny all; }`. Vite's dependency
pre-bundler writes to `node_modules/.vite/` by default, so `.vite/deps/cesium.js`
returns **403** and the app hangs forever on its splash with **no console error**.

Fixed by `deploy/vite.config.docker.js`, which sets `cacheDir: 'vite-cache'`.
Never revert that. Reported upstream to the host as xCloudDev/xCloud#6933.

### 3. Browser caches the module graph

After any deploy that changes how modules are served, a normal reload is not
enough — Chrome replays the old graph with stale hashed paths. **Hard reload
(Cmd/Ctrl+Shift+R).** This has caused two false "it's still broken" diagnoses.

### 4. There are TWO Google keys, and they are not interchangeable

| Variable | Restriction | Used by |
|---|---|---|
| `GOOGLE_MAPS_API_KEY` | HTTP referrer `https://gods-eye.asif.dev/*` | Browser — Map Tiles, injected into the bundle, visible in devtools |
| `GOOGLE_MAPS_SERVER_API_KEY` | IP `23.95.213.126` | Server — `/api/google/*` Places proxy |

A referrer-restricted key **cannot** be used server-side (no referrer is sent) and
**cannot** be used with the Geocoding web service at all — Google rejects it with
*"API keys with referer restrictions cannot be used with this API."* This is why
place search routes through the server proxy (see `textSearchFallback` in
`src/locations.js`).

### 5. The in-app key panel is dead in production, by design

`src/keySetupCore.mjs` refuses any request carrying `x-forwarded-*`, `via`,
`x-real-ip` or `cf-*` headers. Behind nginx every request has them, so the POWER UP
panel always 403s. **This is correct** — it stops the public writing to your `.env`.
Set keys in the xCloud site Environment editor instead. Do not "fix" this.

---

## How to change something

1. Branch. **Never commit to `main`.**
2. Prefer `deploy/` (deployment-only overrides) over editing upstream app code.
   Every line you change in `src/` or `server/` is a line to reconcile at rebase.
3. When you must touch upstream code, comment *why* at the call site.
4. Open a PR with a real note: symptom, evidence, root cause, fix, alternatives
   considered. The PR is the review.
5. Merging to `main` auto-deploys. Verify the live site afterwards — do not trust
   the deploy status alone.

## How to verify

Never trust a green deploy. Check the thing itself:

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://gods-eye.asif.dev/
```

The site is behind Cloudflare Access, so `curl` returns **302 to the Access login** —
that is the correct, healthy response. To test app endpoints, open the site in a
signed-in browser and use the devtools console:

```js
await (await fetch('/api/opensky?lamin=24&lamax=26&lomin=54&lomax=56')).status
await (await fetch('/api/google/text-search?q=Dubai%20Marina')).json()
```

Useful checks: the served bundle should contain the injected keys, and
`/vite-cache/deps/cesium.js` should return 200 (not `/node_modules/.vite/...`).
