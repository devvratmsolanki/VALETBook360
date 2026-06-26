# Slim single-stage image for the realtime gateway (Slice 1.5).
FROM node:24-alpine

# wget is part of busybox in alpine; used by the healthcheck below.
WORKDIR /app

# Install production deps first for layer caching. There's no package-lock in
# this repo, so use `npm install` (not `npm ci`) with --omit=dev.
COPY package.json ./
RUN npm install --omit=dev && npm cache clean --force

# Application source.
COPY src ./src

# Run as the built-in unprivileged "node" user, never root.
USER node

EXPOSE 8090

# Container-local health probe used by docker/compose.
HEALTHCHECK --interval=10s --timeout=5s --start-period=10s --retries=5 \
  CMD wget -qO- http://localhost:8090/healthz | grep -q UP || exit 1

CMD ["node", "src/server.js"]
