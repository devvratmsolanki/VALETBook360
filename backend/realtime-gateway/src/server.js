'use strict';

/**
 * Realtime gateway entrypoint (Slice 1.5).
 *
 * Wiring overview:
 *   - HTTP server hosts both the Socket.IO endpoint and a plain GET /healthz
 *     probe (handled before the request reaches the Socket.IO engine).
 *   - Socket.IO uses the @socket.io/redis-adapter so multiple gateway instances
 *     share rooms and broadcasts (doc 10.6). The adapter needs its OWN dedicated
 *     pub/sub pair of redis clients; the sub client of that pair is put into
 *     Redis "subscriber mode" for the adapter's internal channels, so it must
 *     NOT be reused for our application fan-out.
 *   - A THIRD dedicated subscriber client drives the transaction-event fan-out
 *     (see fanout.startFanout) on the `valet.tx.events` channel.
 *
 * config.js throws at require-time if JWT_SECRET is missing/short — we let that
 * propagate so the process exits non-zero with a clear message (fail-fast).
 */

const http = require('http');

let config;
try {
  config = require('./config');
} catch (err) {
  // config validation failed (e.g. missing JWT_SECRET). Fail loud + non-zero.
  // logger may itself be fine, but keep this dependency-free to be safe.
  process.stderr.write(
    JSON.stringify({
      ts: new Date().toISOString(),
      level: 'error',
      msg: 'fatal: configuration error at boot',
      error: err.message,
    }) + '\n',
  );
  process.exit(1);
}

const { Server } = require('socket.io');
const { createAdapter } = require('@socket.io/redis-adapter');

const logger = require('./logger');
const redis = require('./redis');
const { authMiddleware, joinClaimRooms } = require('./auth');
const { startFanout } = require('./fanout');
const { authorizeTxJoin } = require('./txAuthorize');

// --- Security headers -------------------------------------------------------
// Applied to EVERY HTTP response this server emits (healthz, 404 fallback, and
// — by setting them up-front on the raw res — any Socket.IO handshake response
// that flows through this same http.Server). These are cheap, static, and safe
// to send broadly on an API/WebSocket endpoint.
//
// HSTS is included but only takes effect over HTTPS; in prod TLS terminates at
// the reverse proxy, so the browser sees HTTPS there. Sending it here is
// harmless (ignored over plain HTTP) and means it's present end-to-end.
function applySecurityHeaders(res) {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'no-referrer');
  // API/WS endpoint serves no HTML/JS/CSS of its own -> lock everything down.
  res.setHeader('Content-Security-Policy', "default-src 'none'");
  // Harmless over plain HTTP; enforced once TLS terminates at the proxy.
  res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
}

// --- HTTP server with a dependency-free health endpoint ---------------------
// We answer GET /healthz here, before Socket.IO's engine sees the request.
// Socket.IO attaches its own listeners for its handshake path; any request we
// don't explicitly handle falls through to it.
//
// Health logic: all three ioredis clients (adapterPub, adapterSub, eventsSub)
// must be in 'ready' state. ioredis exposes a `.status` property that reflects
// the current connection state ('wait','connecting','connect','ready','end', etc.).
// If any client is not 'ready', we return 503 DOWN so the compose healthcheck
// (which greps for 'UP') fails and the container is marked unhealthy — preventing
// traffic from being routed to a gateway that cannot fan out events.
const httpServer = http.createServer((req, res) => {
  // Stamp security headers on every response before we branch. Socket.IO's
  // engine, which shares this server, also benefits from these on its handshake
  // responses (it only adds its own CORS headers on top, never removing these).
  applySecurityHeaders(res);
  if (req.method === 'GET' && (req.url === '/healthz' || req.url === '/healthz/')) {
    // adapterPub, adapterSub, eventsSub are declared below; the healthz handler
    // is only invoked AFTER start() wires them up, so they are always in scope.
    const redisReady =
      adapterPub.status === 'ready' &&
      adapterSub.status === 'ready' &&
      eventsSub.status === 'ready';
    if (redisReady) {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ status: 'UP' }));
    } else {
      res.writeHead(503, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        status: 'DOWN',
        details: {
          'adapter-pub': adapterPub.status,
          'adapter-sub': adapterSub.status,
          'events-sub': eventsSub.status,
        },
      }));
    }
    return;
  }
  // Anything else that isn't a Socket.IO handshake -> 404.
  // (Socket.IO intercepts its own path via the 'request' listener it adds.)
  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ status: 'not_found' }));
});

// --- CORS origin allowlist --------------------------------------------------
// Read from the same CORS_ALLOWED_ORIGINS env var as the Java services so that
// a single compose/.env line controls the allowed origins across the whole stack.
// Dev default: localhost on any port (Flutter hot-reload + web dev-server).
// In staging/prod set: CORS_ALLOWED_ORIGINS=https://app.example.com,...
//
// Socket.IO accepts an array of exact origins, a RegExp, or a function. We
// convert the comma-separated list to an array of strings. If a wildcard port
// pattern like "http://localhost:*" is needed for local dev, the origin
// validator function below matches it via a prefix check.
const rawAllowedOrigins = (process.env.CORS_ALLOWED_ORIGINS || 'http://localhost:*,http://127.0.0.1:*')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);

/**
 * Socket.IO origin validator. Called for every handshake with the request
 * origin (or undefined for same-origin / non-browser).
 * - If no origin header is present (e.g. Flutter native, server-to-server),
 *   allow — non-browser clients are not subject to SOP.
 * - If the origin exactly matches an allowlist entry, allow.
 * - If an allowlist entry ends with ':*', allow any port on that scheme+host.
 * - Otherwise, deny with an explicit error.
 */
function corsOriginValidator(origin, callback) {
  if (!origin) {
    // No-origin requests: native app, curl, server-to-server. Permit.
    return callback(null, true);
  }
  for (const allowed of rawAllowedOrigins) {
    if (allowed === origin) {
      return callback(null, true);
    }
    // Pattern: "http://localhost:*" → match any port on that prefix.
    if (allowed.endsWith(':*')) {
      const prefix = allowed.slice(0, -1); // strip trailing '*'
      if (origin.startsWith(prefix)) {
        return callback(null, true);
      }
    }
  }
  logger.warn('cors: origin rejected', { origin });
  return callback(new Error(`Origin ${origin} not allowed by CORS policy`));
}

// --- Socket.IO server -------------------------------------------------------
const io = new Server(httpServer, {
  // CORS driven by CORS_ALLOWED_ORIGINS env var (same value as the Java services).
  // Production must set this to the exact Flutter/web app origins.
  cors: {
    origin: corsOriginValidator,
    methods: ['GET', 'POST'],
  },
  // Heartbeat: drop dead connections within ~25s without being chatty.
  pingTimeout: 20000,
  pingInterval: 25000,
});

// --- Redis clients ----------------------------------------------------------
// Adapter pair (cross-instance broadcasting). The sub client goes into Redis
// subscriber mode for the adapter's own channels — keep it separate from fan-out.
const adapterPub = redis.createClient('adapter-pub');
const adapterSub = redis.createClient('adapter-sub');
// Dedicated subscriber for the application event fan-out.
const eventsSub = redis.createClient('events-sub');

io.adapter(createAdapter(adapterPub, adapterSub));

// --- Auth + connection lifecycle -------------------------------------------
io.use(authMiddleware());

io.on('connection', (socket) => {
  // Join only the rooms the verified JWT claims entitle this socket to.
  joinClaimRooms(socket);

  const p = socket.data.principal;
  logger.info('socket connected', {
    socketId: socket.id,
    driverId: p.userId,
    role: p.role,
    company: p.companyId,
    location: p.locationId,
  });

  // Optional detail subscription: a client viewing one transaction can opt into
  // its tx:{id} room. Two gates, in order:
  //   1. Strict id validation — only a non-empty string id is allowed.
  //   2. ROOM-OWNERSHIP — the socket may join tx:{id} ONLY if it is entitled to
  //      read that transaction. We do NOT trust the client; we ask the
  //      transaction-service (forwarding the socket's own verified token) and
  //      reuse its getByIdScoped tenant/role guard: 200 => entitled => join,
  //      anything else (incl. timeout/error) => DENY (fail-closed). This closes
  //      the cross-tenant leak where any client could join another tenant's
  //      tx:{id} room and receive its tx:status / tx:assigned events.
  socket.on('subscribe:tx', async (rawId, ack) => {
    const id = typeof rawId === 'string' ? rawId.trim() : '';
    if (!id) {
      logger.warn('subscribe:tx rejected: invalid id', { socketId: socket.id });
      if (typeof ack === 'function') ack({ ok: false, error: 'invalid id' });
      return;
    }

    let entitled = false;
    try {
      entitled = await authorizeTxJoin(id, socket.data.token);
    } catch (err) {
      // Defensive: authorizeTxJoin already fails closed, but never let a
      // throw here accidentally fall through to a join.
      logger.error('subscribe:tx authorize threw; denying', {
        socketId: socket.id,
        txId: id,
        error: err && err.message ? err.message : String(err),
      });
      entitled = false;
    }

    if (!entitled) {
      logger.warn('subscribe:tx denied: not entitled', {
        socketId: socket.id,
        txId: id,
        driverId: socket.data.principal && socket.data.principal.userId,
      });
      if (typeof ack === 'function') ack({ ok: false, error: 'forbidden' });
      return;
    }

    socket.join(`tx:${id}`);
    logger.info('socket subscribed to tx room', { socketId: socket.id, txId: id });
    if (typeof ack === 'function') ack({ ok: true, room: `tx:${id}` });
  });

  socket.on('disconnect', (reason) => {
    logger.info('socket disconnected', { socketId: socket.id, reason });
  });
});

// --- Boot -------------------------------------------------------------------
async function start() {
  // Wire the dedicated fan-out subscriber to the events channel.
  await startFanout(io, eventsSub);

  httpServer.listen(config.gatewayPort, () => {
    logger.info('realtime gateway listening', {
      port: config.gatewayPort,
      channel: config.eventsChannel,
    });
  });
}

start().catch((err) => {
  logger.error('fatal: failed to start gateway', { error: err.message });
  process.exit(1);
});

// --- Graceful shutdown ------------------------------------------------------
let shuttingDown = false;
async function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  logger.info('shutdown initiated', { signal });

  // Stop accepting new sockets/HTTP, then drain the redis clients.
  const closeIo = new Promise((resolve) => io.close(() => resolve()));

  // Bound the shutdown so a wedged client can't hang the container forever.
  const timeout = new Promise((resolve) => setTimeout(resolve, 5000));
  await Promise.race([closeIo, timeout]);

  await Promise.allSettled([
    adapterPub.quit(),
    adapterSub.quit(),
    eventsSub.quit(),
  ]);

  logger.info('shutdown complete', { signal });
  process.exit(0);
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
