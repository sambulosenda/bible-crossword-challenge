# Build the static Astro site, then serve it with Caddy. Railway builds this with
# the service Root Directory set to `web`, so the build context is web/.

# --- build stage -----------------------------------------------------------
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

# --- serve stage -----------------------------------------------------------
FROM caddy:2-alpine
COPY Caddyfile /etc/caddy/Caddyfile
COPY --from=build /app/dist /srv
# Railway injects $PORT; the Caddyfile binds to it.
