'use strict';

const config = require('./config');
const logger = require('./logger');

/**
 * Authorize a socket's request to join the `tx:{id}` detail room.
 *
 * The gateway has NO database connection and must stay lightweight, so instead
 * of re-implementing tenant/role checks we REUSE the transaction-service's own
 * server-side guard as the single source of truth:
 *
 *   GET {CORE_INTERNAL_URL}/api/transactions/{id}
 *   Authorization: Bearer <the socket's own, already-verified access token>
 *
 * transaction-service.getByIdScoped grants the read only to:
 *   - an operator-capable caller (valet/manager/admin) in the tx's company, OR
 *   - the driver currently assigned to retrieve the tx.
 * Everyone else gets 403 NOT_YOUR_TRANSACTION (and a non-existent id is 403 for
 * drivers / 404 for operators). Therefore:
 *
 *   HTTP 200  -> caller IS entitled  -> allow the room join.
 *   anything else (403/404/5xx/network error/timeout) -> DENY (fail-closed).
 *
 * Fail-closed is deliberate: a slow or unreachable transaction-service must
 * never be able to grant access to a tenant's detail room.
 *
 * @param {string} txId   strictly-validated transaction id (non-empty string)
 * @param {string} token  the socket's verified access JWT (socket.data.token)
 * @returns {Promise<boolean>} true only on a 200 response
 */
async function authorizeTxJoin(txId, token) {
  if (!token) {
    // No token captured (should not happen post-auth) -> fail closed.
    logger.warn('tx authorize denied: no token on socket');
    return false;
  }

  const url = `${config.coreInternalUrl}/api/transactions/${encodeURIComponent(txId)}`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), config.txAuthorizeTimeoutMs);

  try {
    const res = await fetch(url, {
      method: 'GET',
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: 'application/json',
      },
      signal: controller.signal,
    });

    if (res.status === 200) {
      return true;
    }

    // Any non-200 is a denial. 403/404 are the normal "not entitled" path.
    logger.warn('tx authorize denied by transaction-service', {
      txId,
      status: res.status,
    });
    return false;
  } catch (err) {
    // Timeout (AbortError), connection refused, DNS failure, etc. -> deny.
    logger.error('tx authorize failed; denying (fail-closed)', {
      txId,
      error: err && err.message ? err.message : String(err),
    });
    return false;
  } finally {
    clearTimeout(timer);
  }
}

module.exports = { authorizeTxJoin };
