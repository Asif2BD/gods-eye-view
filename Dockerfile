# God's Eye View — container image for self-hosting behind a reverse proxy.
#
# The app's live data layers (OpenSky, adsb.lol, CelesTrak, CCTV, Overpass,
# FIRMS, TomTom, GBFS, terrain heights) are Vite plugins that register only
# `configureServer`, so they exist on the dev server and nowhere else. A
# `vite build` / `vite preview` image would serve the globe with most feeds
# dead. This image therefore runs the same dev server the Pinokio launcher
# runs, bound to every interface so nginx can proxy to it.

FROM node:24-bookworm-slim

# Cesium's build and sharp's postinstall want a compiler toolchain.
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 make g++ ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package.json package-lock.json ./

# vite and vite-plugin-cesium are devDependencies, so dev deps must be
# installed. Puppeteer is only used by the QA scripts — skip its ~150 MB
# Chromium download rather than pulling it into every image build.
ENV PUPPETEER_SKIP_DOWNLOAD=true
RUN npm ci

COPY . .

# allowedHosts opens up only when HOST is 0.0.0.0 — see build/vite.js.
ENV HOST=0.0.0.0
ENV PORT=4173
EXPOSE 4173

# Not `npm run dev`: the deployment config relocates Vite's cache directory
# out of `node_modules/.vite/` so nginx's dot-segment deny rule cannot
# block the pre-bundled Cesium chunk. See deploy/vite.config.docker.js.
CMD ["npx", "vite", "--config", "deploy/vite.config.docker.js"]
