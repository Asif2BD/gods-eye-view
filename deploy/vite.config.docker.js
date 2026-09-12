// Deployment-only Vite config for the container image.
//
// xCloud's nginx vhost carries the standard hardening rule that denies any
// request path containing a dot-segment (`location ~ /\. { deny all; }`).
// Vite pre-bundles heavy dependencies into `node_modules/.vite/deps/` and
// serves them from that URL, so `/node_modules/.vite/deps/cesium.js` returns
// 403 while every other module loads fine. The app then hangs forever on
// "Initializing photorealistic world...", because Cesium is the one
// dependency large enough to be pre-bundled.
//
// Moving the cache directory to a name without a leading dot keeps the served
// URL clear of the deny rule. Everything else is inherited unchanged from the
// upstream standalone config, so this stays a thin deployment override rather
// than a fork of application configuration.

import { defineConfig } from 'vite';
import standalone from '../server/standalone/vite.config.js';

export default defineConfig(async (env) => {
  const base = typeof standalone === 'function' ? await standalone(env) : standalone;
  return { ...base, cacheDir: 'vite-cache' };
});
