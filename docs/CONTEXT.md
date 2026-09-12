# Project context

Why this fork exists, what has been decided, and what is still open. Written so that
a person or agent picking this up cold does not have to re-derive any of it.

## Goal

Run [God's Eye View](https://github.com/bilawalsidhu/gods-eye-view) — a Cesium-based
real-time intelligence globe — as a **private, self-hosted instance** at
`https://gods-eye.asif.dev`, for personal exploration. Not a product, not public.

Non-goals: hardening it into a production service, or diverging from upstream beyond
what self-hosting requires.

## Where it runs

| | |
|---|---|
| Host | xCloud, server `RackNerd-8GB-BF2025`, `23.95.213.126` |
| Type | Docker (`docker-compose.yml`), nginx reverse proxy → container port 4173 |
| Deploy | Git push-deploy from `main` of this fork |
| DNS + TLS | Cloudflare, created and managed by xCloud's Cloudflare integration — **never hand-create the A record** |
| Access | Cloudflare Zero Trust (team `wphostreview`), app `gods-eye`, policy allows one email, one-time PIN |

## Architecture decision: why the container runs a dev server

The live-data providers are Vite plugins registered via `configureServer` only, so
they exist on the dev server and nowhere else. A production build serves the globe
with most feeds dead. The container therefore runs `npx vite` — which is also what the
project's own Pinokio launcher does locally. `build/vite.js` widens `allowedHosts`
precisely when `HOST=0.0.0.0`, so upstream anticipated being reverse-proxied.

Consequences accepted: slow first load (~10 MB Cesium bundle, ~300 unbundled modules),
and a dev server facing the internet — mitigated by putting Cloudflare Access in front.

## Credentials and who pays

| Key | Scope | Billing |
|---|---|---|
| `GOOGLE_MAPS_API_KEY` | Browser; referrer-locked to the site | GCP `gods-eye-view-508410` → **WPDev Billing Account**, $50/mo budget "gods-eye-view maps", alerts at $25/$45/$50 |
| `GOOGLE_MAPS_SERVER_API_KEY` | Server; IP-locked to the host; Places API (New) | same project |
| `CESIUM_ION_TOKEN` | Client-exposed | Cesium ion free personal tier |
| `OPENAI_API_KEY` | Server only; voice + HUD summaries | OpenAI, billed per minute of audio |

Note: the Google spend lands on a **company** billing account for a personal project.
That was a deliberate choice; a personal billing account had hit its project cap.

Optional, all free-tier, not yet configured: `TOMTOM_API_KEY` (live congestion
colouring — without it the traffic layer runs its own simulation), `FIRMS_MAP_KEY`
(NASA active fires), `AISSTREAM_API_KEY` (live vessels).

## Decisions worth not relitigating

- **Static build rejected.** Kills the live layers. See AGENTS.md §1.
- **`cacheDir: 'vite-cache'`** rather than an nginx rule allowing `/node_modules/.vite/`.
  Keeping the fix in the repo means it survives site recreation and does not weaken a
  hardening rule that is otherwise correct.
- **Place search routes through the server proxy.** Google's Geocoding web service
  rejects referrer-restricted keys, and the browser key must be referrer-restricted.
- **In-app key panel left disabled.** It is a security feature, not a bug.
- **Cloudflare Access with one-time PIN**, not a Google IdP. PIN needs no identity
  provider setup; the Google/passkey upgrade slots in later without changing the app
  or the policy.

## CI/CD

- **CI:** upstream GitHub Actions (`.github/workflows/ci.yml`) — unit tests, format
  check, package-boundary check. Runs on PRs to this fork.
- **CD:** merge to `main` → xCloud webhook → rebuild image → recreate container.
  Environment variables are **not** in the repo; they live in the xCloud site
  Environment editor and are injected at container start, so an env change needs a
  redeploy to take effect.
- **Verification is manual and mandatory.** A successful deploy has twice coexisted
  with a completely broken page. Always load the site and check a live layer.

## Known issues / open items

- First load is slow by design (dev server, unbundled modules).
- TomTom, FIRMS and AISStream keys not yet added — those layers are simulated or empty.
- Voice control is billed per minute; no usage cap is configured on the OpenAI side yet.
- Nine issues filed against the host platform, tracked at xCloudDev/xCloud#6932;
  the serving-layer bug is xCloudDev/xCloud#6933.
