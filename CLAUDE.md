# CLAUDE.md

Instructions for Claude Code in this repository.

**Read [AGENTS.md](AGENTS.md) first** — it holds the five non-obvious traps
(dev-server-only providers, the nginx dot-path 403, browser module caching, the two
distinct Google keys, and the deliberately-dead key panel). Everything there applies
to you. This file adds only Claude-specific working rules.

## Working rules

- **Never commit to `main`.** Branch, then PR with a proper note. The note is the
  review: symptom → evidence → root cause → fix → alternatives considered.
- **Verify, do not assume.** A green xCloud deploy does not mean the app works. Check
  the actual endpoint or render. Two bugs in this repo's history presented as a
  perfectly healthy deploy with a hanging page and no console error.
- **Prefer `deploy/` overrides to editing `src/` or `server/`.** This is a fork of an
  active upstream; minimise rebase pain.
- **Secrets never enter the repo.** `.env` is gitignored and the Docker build excludes
  it. Keys live in the xCloud site Environment editor. Never paste a key into a commit,
  a PR body, or a comment.
- **Hard-reload before concluding anything is broken** in the browser. See AGENTS.md §3.

## Common tasks

| Task | How |
|---|---|
| Add/change an API key | xCloud site → Docker Compose → Environment → edit → **Update Environment** → redeploy |
| Deploy | Merge to `main` (auto-deploys), or xCloud → **Deploy Now** |
| Check a live layer | Signed-in browser console: `await (await fetch('/api/opensky?...')).status` |
| Find why the globe hangs | devtools Network, look for a **403 or 503 on one module** — usually a dep path |

## Local development

```bash
npm ci
npm run doctor       # environment check
npm run dev          # http://localhost:4173
npm test             # unit tests
npm run format:check
```

Requires **Node 24.14+ or 26** (see `engines` in `package.json`). Node 25 is EOL and
the setup doctor warns about it.

The app runs fully keyless for local work — Esri imagery plus flights, military,
satellites, quakes, cameras, radio and launches all work with no API keys at all.
