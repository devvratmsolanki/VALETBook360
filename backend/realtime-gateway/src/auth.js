'use strict';

const jwt = require('jsonwebtoken');
const config = require('./config');
const logger = require('./logger');

/**
 * Extract the bearer token from a Socket.IO handshake. Two accepted sources,
 * in priority order:
 *   1. socket.handshake.auth.token            (socket.io-client `auth` option)
 *   2. Authorization: Bearer <t> handshake header
 */
function extractToken(handshake) {
  const authToken = handshake && handshake.auth && handshake.auth.token;
  if (typeof authToken === 'string' && authToken.length > 0) {
    return authToken;
  }
  const header =
    handshake &&
    handshake.headers &&
    (handshake.headers.authorization || handshake.headers.Authorization);
  if (typeof header === 'string' && header.startsWith('Bearer ')) {
    return header.slice('Bearer '.length).trim();
  }
  return null;
}

/**
 * Socket.IO middleware factory. Verifies the access JWT (HS256, shared secret,
 * required issuer, typ === "access") and stashes the *server-trusted* claims on
 * socket.data. Rooms are later derived ONLY from these claims — never from
 * client-supplied data — so a client can only receive its own events.
 */
function authMiddleware() {
  return (socket, next) => {
    const token = extractToken(socket.handshake);
    if (!token) {
      logger.warn('handshake rejected: no token', { socketId: socket.id });
      return next(new Error('unauthorized'));
    }

    let claims;
    try {
      claims = jwt.verify(token, config.jwtSecret, {
        algorithms: ['HS256'],
        issuer: config.jwtIssuer,
      });
    } catch (err) {
      logger.warn('handshake rejected: bad token', {
        socketId: socket.id,
        error: err.message,
      });
      return next(new Error('unauthorized'));
    }

    if (claims.typ !== 'access') {
      logger.warn('handshake rejected: wrong token type', {
        socketId: socket.id,
        typ: claims.typ,
      });
      return next(new Error('unauthorized'));
    }

    if (!claims.sub) {
      logger.warn('handshake rejected: missing sub', { socketId: socket.id });
      return next(new Error('unauthorized'));
    }

    // Only trusted, signed claims survive past this point.
    socket.data.principal = {
      userId: String(claims.sub),
      role: claims.role || null,
      companyId: claims.companyId ? String(claims.companyId) : null,
      locationId: claims.locationId ? String(claims.locationId) : null,
    };
    // Stash the verified access token so handlers (e.g. subscribe:tx) can
    // forward it to the transaction-service to reuse its server-side
    // tenant/role authorization as the single source of truth. This is the
    // SAME token we just verified above — never client-trusted beyond its
    // signature, and only ever sent to our own internal service over the
    // compose network.
    socket.data.token = token;
    return next();
  };
}

/**
 * Join a freshly-authenticated socket to the rooms its claims entitle it to.
 * Derived from the token only:
 *   - driver:{sub}            (always)
 *   - company:{companyId}     (if present)
 *   - location:{locationId}   (if present)
 */
function joinClaimRooms(socket) {
  const p = socket.data.principal;
  const rooms = [`driver:${p.userId}`];
  socket.join(`driver:${p.userId}`);

  if (p.companyId) {
    socket.join(`company:${p.companyId}`);
    rooms.push(`company:${p.companyId}`);
  }
  if (p.locationId) {
    socket.join(`location:${p.locationId}`);
    rooms.push(`location:${p.locationId}`);
  }

  logger.info('socket joined rooms', {
    socketId: socket.id,
    driverId: p.userId,
    role: p.role,
    company: p.companyId,
    location: p.locationId,
    rooms,
  });
}

module.exports = { authMiddleware, joinClaimRooms, extractToken };
