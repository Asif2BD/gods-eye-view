# essence.md — gods-eye.asif.dev

**Everything you need to take over this deployment.** Written as a handover: what it
is, how it got here, how to deploy it, how to verify it, and every trap that cost
time. If you read one file, read this one.

- **Live:** https://gods-eye.asif.dev (behind Cloudflare Access — one allowed email)
- **Repo:** `Asif2BD/gods-eye-view`, a fork of `bilawalsidhu/gods-eye-view`
- **Owner:** M Asif Rahman (asif2bd@gmail.com)
- **Built:** 12–13 September 2026

---

## 1. What this is and why

[God's Eye View](https://github.com/bilawalsidhu/gods-eye-view) is a Cesium-based
real-time intelligence globe: live aircraft, military traffic, satellites, ships,
earthquakes, fires, public traffic cameras, radio, and voice control over a
photorealistic 3D Earth.

This fork exists for exactly one reason: **to self-host it privately**. It is a
personal exploration instance, not a product and not public. Upstream is active, so
**keep divergence minimal** — every line changed in `src/` or `server/` is a line to
reconcile at the next rebase.

---

## 2. Infrastructure at a glance

| Layer | Value |
|---|---|
| Host | xCloud, server `RackNerd-8GB-BF2025` |
| Server IP | `23.95.213.126` (6 cores, 8 GB RAM, 155 GB disk) |
| Site UUID | `626a6c85-ba57-4cc9-988f-2ae66cc96178` |
| Site type | `docker-compose`, nginx reverse proxy → container port `4173` |
| Repo/branch | `Asif2BD/gods-eye-view` @ `main`, push-deploy enabled |
| DNS + TLS | Cloudflare, **created and managed by xCloud's Cloudflare integration** |
| Access control | Cloudflare Zero Trust, team `wphostreview`, app `gods-eye` |
| GCP project | `gods-eye-view-508410` (billed to **WPDev Billing Account**) |

**Never hand-create the DNS A record.** xCloud's "Manage DNS & SSL with Cloudflare"
toggle does it, proxied. Creating it manually produces a broken, unproxied record.

---

## 3. The architecture decision that explains everything

**The container runs the Vite _dev server_, not a production build.**

This looks wrong. It is deliberate, and reversing it will silently destroy the app.

The live-data providers in `server/providers/` are Vite **plugins**. Most register
only `configureServer`, so they exist on the dev server and nowhere else:

| Provider | Registers | Survives a build? |
|---|---|---|
| OpenSky aircraft | `configureServer` only | ❌ |
| adsb.lol military | `configureServer` only | ❌ |
| CelesTrak satellites | `configureServer` only | ❌ |
| CCTV, Overpass | `configureServer` only | ❌ |
| NASA FIRMS, TomTom, GBFS, terrain | `configureServer` only | ❌ |
| AIS, launches, Places, voice, radio | both hooks | ✅ |

A static build serves a pretty globe with almost no live data. `vite preview` loses
aircraft, satellites, cameras, fires and traffic. So the image runs `npx vite` with
`HOST=0.0.0.0` — which is also exactly what the project's own Pinokio launcher does.
`build/vite.js` widens `allowedHosts` precisely when `HOST` is `0.0.0.0`, so upstream
clearly anticipated being reverse-proxied.

**Accepted consequences:** slow first load (~10 MB Cesium bundle + ~300 unbundled
modules) and a dev server facing the internet — mitigated by Cloudflare Access.

---

## 4. CI/CD

### Pipeline

```
local branch ──PR──> main ──webhook──> xCloud ──docker build──> container recreate
                                                                        │
                                                        nginx :4173 <────┘
                                                                        │
                                              Cloudflare (proxy + Access) ──> user
```

### CI

Upstream GitHub Actions (`.github/workflows/`) run on PRs: unit tests, format check,
package-boundary check. No deployment happens from CI.

### CD

Merging to `main` fires the xCloud webhook, which rebuilds the image and recreates the
container. Roughly 2–4 minutes (`npm ci` dominates).

Manual deploy when you changed env but not code:

- xCloud dashboard → site → **Deploy Now**, or
- API: `POST /sites/{uuid}/git/deploy` (xCloud MCP: `sites_git_deploy`)

### Environment variables are NOT in the repo

`.env` is gitignored and excluded from the Docker build context. Keys live in
**xCloud → site → Docker Compose → Environment**, injected at container start.

> **An env change requires a redeploy to take effect.** Saving the editor alone does
> nothing — Vite reads env at process start, and the client-exposed keys are baked in
> by `define` at that moment.

### Rules

1. **Never commit to `main`.** Branch → PR → merge.
2. The PR note is the review: symptom → evidence → root cause → fix → alternatives.
3. Prefer `deploy/` overrides to editing `src/` or `server/`.
4. **Verify the live site after every deploy.** Never trust deploy status alone.

---

## 5. Credentials

| Variable | Where used | Restriction | Notes |
|---|---|---|---|
| `GOOGLE_MAPS_API_KEY` | Browser | HTTP referrer `https://gods-eye.asif.dev/*` | Injected into the bundle, **visible in devtools** — the referrer lock is the only protection |
| `GOOGLE_MAPS_SERVER_API_KEY` | Server | IP `23.95.213.126`, Places API (New) | Never reaches the browser |
| `CESIUM_ION_TOKEN` | Browser | — | Free personal tier |
| `OPENAI_API_KEY` | Server | — | Voice + HUD summaries, **billed per minute of audio** |

Optional, free tier, not yet configured: `TOMTOM_API_KEY` (live congestion),
`FIRMS_MAP_KEY` (active fires), `AISSTREAM_API_KEY` (live vessels).

**Cost controls:** GCP budget "gods-eye-view maps" — $50/month scoped to this project,
alerts at $25/$45/$50. A budget alerts; it does not stop spend. Cloudflare Access is
what actually prevents strangers consuming quota. No cap is set on OpenAI yet.

> The Google spend lands on a **company** billing account for a personal project. That
> was deliberate — the personal billing account had hit its project cap.

---

## 6. The five traps

Each of these cost real debugging time. None are obvious.

### 6.1 nginx denies dot-segment paths → app hangs with no error

xCloud's vhost carries `location ~ /\. { deny all; }`. Vite pre-bundles deps into
`node_modules/.vite/`, so `.vite/deps/cesium.js` returned **403**. Cesium is the only
dep large enough to be pre-bundled, and it is the one module the globe cannot start
without.

Presentation: site returns 200, ~300 other modules load, HMR connects, **no console
error**, app sits on its splash forever, and xCloud reports `deployed / 100% / no
failed steps`.

**Fix:** `deploy/vite.config.docker.js` sets `cacheDir: 'vite-cache'`. Never revert.
Reported to the platform as xCloudDev/xCloud#6933.

### 6.2 The browser caches the module graph

After a deploy that changes served module paths, a normal reload replays the old graph
with stale hashes. This produced two false "still broken" diagnoses.
**Always hard-reload (⌘⇧R / Ctrl+Shift+R) before concluding anything.**

### 6.3 Two Google keys, not interchangeable

A referrer-restricted key **cannot** be used server-side (no referrer is sent) and
**cannot** be used with the Geocoding web service at all:

```
REQUEST_DENIED — "API keys with referer restrictions cannot be used with this API."
```

That is why place search routes through `/api/google/text-search` (server proxy, IP-
restricted key) via `textSearchFallback` in `src/locations.js`. A browser-safe key and
the Geocoding web service are mutually exclusive — this cannot be fixed in the console.

### 6.4 The in-app key panel is dead in production, by design

`src/keySetupCore.mjs` refuses any request carrying `x-forwarded-*`, `via`, `x-real-ip`
or `cf-*` headers. Behind nginx every request has them, so the POWER UP panel always
403s with *"Provider Settings does not answer proxied requests."*

**This is correct.** It stops the public writing to your `.env`. Do not "fix" it. Set
keys in the xCloud Environment editor.

### 6.5 Deploy success ≠ working app

Twice, a perfectly green deploy coexisted with a completely broken page. The status API
reports provisioning, not application health. Verification is manual and mandatory.

---

## 7. Verification runbook

### From a shell

```bash
# Expect 302 to the Access login — this is CORRECT and healthy
curl -s -o /dev/null -w '%{http_code}\n' https://gods-eye.asif.dev/

# DNS should resolve to Cloudflare proxy IPs, not the origin
dig +short @1.1.1.1 gods-eye.asif.dev A
```

If you get 200 with app HTML instead of a 302, **Access is not protecting the site.**

### From a signed-in browser console

```js
// Live layers
await (await fetch('/api/opensky?lamin=24&lamax=26&lomin=54&lomax=56')).status  // 200
await (await fetch('/api/celestrak/stations')).status                            // 200
await (await fetch('/api/launches')).status                                      // 200

// Place search (the server proxy path)
await (await fetch('/api/google/text-search?q=Gulshan%202%20Circle%20Dhaka')).json()

// Voice
(await fetch('/api/realtime/token', {method:'POST'})).status                     // 200

// The dep path that must NOT be used
await (await fetch('/vite-cache/deps/cesium.js')).status                          // 200
await (await fetch('/node_modules/.vite/deps/cesium.js')).status                  // 403 (expected)
```

### Known-good responses

| Endpoint | Healthy |
|---|---|
| `/api/opensky` | 200, ~1 MB |
| `/api/celestrak/stations` | 200, live ISS TLE |
| `/api/google/text-search` | 200 with `places[0].latitude` |
| `/api/firms` | `503 {"error":"no_key"}` until `FIRMS_MAP_KEY` is set |
| `/api/realtime/token` | 200 (or `503 OPENAI_API_KEY is not set`) |

---

## 8. Feature status

| Feature | Status | Needs |
|---|---|---|
| Photorealistic 3D globe | ✅ | Google + Cesium keys (done) |
| Place search | ✅ | Server proxy (fixed in PR #3) |
| Aircraft, military, satellites, launches, quakes | ✅ | nothing — keyless, global |
| Radio | ✅ | nothing |
| Voice control | ✅ | `OPENAI_API_KEY` (done) |
| Public CCTV | ⚠️ regional | **Austin 250 / California 300 / London 250 — no other coverage** |
| Traffic | ⚠️ simulated | `TOMTOM_API_KEY` for live congestion (free, 200K tiles/mo) |
| Active fires | ❌ | `FIRMS_MAP_KEY` (free) |
| Live vessels | ❌ | `AISSTREAM_API_KEY` (free) |

**CCTV is a data-source limit, not configuration.** The app ships three public feeds.
Custom packs are supported via `config/cctv_sources.*.json` + `CCTV_SOURCES_FILE`;
each entry is a camera with a feed URL and a pose (lat/lon/heading/pitch/fov).

---

## 9. Change history

| PR | What | Why |
|---|---|---|
| [#1](https://github.com/Asif2BD/gods-eye-view/pull/1) | Dockerfile, compose, dockerignore | Self-host; runs the dev server deliberately (§3) |
| [#2](https://github.com/Asif2BD/gods-eye-view/pull/2) | `deploy/vite.config.docker.js` | nginx dot-path 403 hung the app (§6.1) |
| [#3](https://github.com/Asif2BD/gods-eye-view/pull/3) | `textSearchFallback` + AGENTS/CLAUDE/CONTEXT docs | Geocoding rejects referrer keys (§6.3) |

---

## 10. Platform issues filed upstream

Nine issues against `xCloudDev/xCloud`, tracked by **#6932**:

| # | Issue |
|---|---|
| 6924 | No OpenAPI spec — request shapes and enums undiscoverable (**root cause**) |
| 6925 | Validation errors omit allowed enum values (`domain.mode`) |
| 6926 | Nested validation reveals requirements one layer at a time |
| 6927 | MCP tool schemas type object params as strings |
| 6928 | No compose-scan endpoint |
| 6929 | Cloudflare-managed DNS/SSL unavailable via API |
| 6930 | No dry-run, yet validation is the only contract disclosure |
| 6931 | Dashboard routes reject API UUIDs; no staging-domain endpoint |
| **6933** | **nginx dot-segment deny breaks Vite/Next/Nuxt Docker sites — silent hang** |

#6933 is the one that cost this deployment the most time.

---

## 11. Handover checklist

To take this over you need:

- [ ] GitHub access to `Asif2BD/gods-eye-view`
- [ ] xCloud team access (site `626a6c85-…` on `RackNerd-8GB-BF2025`)
- [ ] Google Cloud access to `gods-eye-view-508410`
- [ ] Cloudflare access to the `asif.dev` zone **and** Zero Trust team `wphostreview`
- [ ] Your email added to the Access policy "Only Asif", or replace it

**First actions on taking over:**

1. Read `AGENTS.md` — the five traps in operational form
2. Load the site, hard-reload, confirm the globe renders and aircraft appear
3. Run the §7 verification block
4. Check the GCP budget is still $50 and alerts point at a monitored address

**Open items:**

- TomTom / FIRMS / AISStream keys not yet added (all free tier)
- No usage cap configured on the OpenAI account — voice is per-minute billed
- Google spend sits on the company billing account (see §5)
- First load is slow by design; only fixable if upstream gives the providers a
  production path
- Access uses one-time PIN; a Google IdP upgrade (passkey / Face ID) slots in without
  changing the app or the policy

---

## 12. Quick reference

```bash
# Local development (Node 24.14+ or 26 required)
npm ci && npm run doctor && npm run dev     # http://localhost:4173
npm test && npm run format:check

# Deploy: merge to main, or xCloud "Deploy Now"
# Env:    xCloud → site → Docker Compose → Environment → Update Environment → redeploy
# Verify: hard-reload, then the console checks in §7
```

**If the app hangs on the splash:** open devtools Network and look for a **single
403/503 on one module**. That is trap §6.1 or a stale cache (§6.2). It will not appear
in the console.
