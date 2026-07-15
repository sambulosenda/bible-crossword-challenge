# Build the static Astro site, then serve it with Caddy. Railway builds this with
# the service Root Directory set to `web`, so the build context is web/.

# --- build stage -----------------------------------------------------------
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
# `npm install` (not `npm ci`): Astro pulls typescript as an optional dep that
# different npm versions lock differently, which makes the strict `npm ci`
# fail on this image's npm. `install` resolves it cleanly and deterministically
# enough for a static build.
RUN npm install --no-audit --no-fund
COPY . .
RUN npm run build

# --- serve stage -----------------------------------------------------------
FROM caddy:2-alpine
COPY Caddyfile /etc/caddy/Caddyfile
COPY --from=build /app/dist /srv
# Railway injects $PORT; the Caddyfile binds to it.
