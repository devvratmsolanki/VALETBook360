'use strict';

/**
 * Centralised, validated configuration read from the environment.
 * Throws at boot if anything required is missing so we fail fast and loud
 * instead of mis-behaving silently.
 */

function readInt(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === '') return fallback;
  const n = Number.parseInt(raw, 10);
  if (Number.isNaN(n)) {
    throw new Error(`Env ${name} must be an integer, got "${raw}"`);
  }
  return n;
}

const JWT_SECRET = process.env.JWT_SECRET;
if (!JWT_SECRET || Buffer.byteLength(JWT_SECRET, 'utf8') < 32) {
  // Same constraint the Java services enforce (HS256 needs >= 32 bytes).
  throw new Error('JWT_SECRET (env) must be set and at least 32 bytes for HS256');
}

module.exports = {
  gatewayPort: readInt('GATEWAY_PORT', 8090),
  redisHost: process.env.REDIS_HOST || 'localhost',
  redisPort: readInt('REDIS_PORT', 6379),
  jwtSecret: JWT_SECRET,
  // Issuer is part of the shared contract minted by auth-service.
  jwtIssuer: process.env.JWT_ISSUER || 'valet-auth',
  // The single pub/sub channel the transaction-service publishes to.
  eventsChannel: process.env.TX_EVENTS_CHANNEL || 'valet.tx.events',
  // Internal base URL of the transaction-service (compose network). Used to
  // authorize tx:{id} room joins by reusing that service's getByIdScoped
  // tenant/role guard — a 200 means the caller is entitled to the tx, anything
  // else means deny (fail-closed). Default targets the compose service name.
  coreInternalUrl: process.env.CORE_INTERNAL_URL || 'http://transaction-service:8082',
  // Hard timeout (ms) for the authorize fetch. On timeout we DENY (fail-closed)
  // so a slow/unreachable transaction-service can never grant a room join.
  txAuthorizeTimeoutMs: readInt('TX_AUTHORIZE_TIMEOUT_MS', 3000),
};
