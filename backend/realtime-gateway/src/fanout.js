'use strict';

const config = require('./config');
const logger = require('./logger');

/**
 * The pinned event envelope published by the transaction-service on the
 * `valet.tx.events` Redis channel. Field names are a hard contract — do NOT
 * rename them here. Recognised event types:
 *   tx:created, tx:status, tx:assigned
 *
 * We accept any well-formed object with an `event` string + an `id`; unknown
 * event names are still fanned out (forward-compatible) but logged at debug.
 */
const KNOWN_EVENTS = new Set(['tx:created', 'tx:status', 'tx:assigned']);

/**
 * Given one parsed envelope, compute the target rooms. Only rooms whose id is
 * present/non-null in the payload are included.
 *
 *   location:{locationId}
 *   company:{companyId}
 *   tx:{id}
 *   driver:{driverId}   (for ANY message carrying a non-null driverId)
 */
function targetRooms(msg) {
  const rooms = [];
  if (msg.locationId != null) rooms.push(`location:${msg.locationId}`);
  if (msg.companyId != null) rooms.push(`company:${msg.companyId}`);
  if (msg.id != null) rooms.push(`tx:${msg.id}`);
  if (msg.driverId != null) rooms.push(`driver:${msg.driverId}`);
  return rooms;
}

/**
 * Handle one raw Redis pub/sub message: parse defensively, then emit the event
 * (named by its `event` field) with the full payload to every target room.
 * A malformed message is logged and skipped — it must never crash the process.
 */
function handleMessage(io, raw) {
  let msg;
  try {
    msg = JSON.parse(raw);
  } catch (err) {
    logger.error('skipped malformed event (JSON parse failed)', {
      error: err.message,
      raw: typeof raw === 'string' ? raw.slice(0, 500) : String(raw),
    });
    return;
  }

  if (!msg || typeof msg !== 'object' || typeof msg.event !== 'string') {
    logger.error('skipped malformed event (no event field)', {
      raw: typeof raw === 'string' ? raw.slice(0, 500) : String(raw),
    });
    return;
  }

  if (!KNOWN_EVENTS.has(msg.event)) {
    logger.debug('forwarding unknown event type', { event: msg.event });
  }

  const rooms = targetRooms(msg);
  if (rooms.length === 0) {
    logger.warn('event had no target rooms; dropping', {
      event: msg.event,
      id: msg.id,
    });
    return;
  }

  // io.to([...rooms]) de-duplicates delivery: a socket in several of these
  // rooms still receives the event exactly once.
  io.to(rooms).emit(msg.event, msg);

  logger.info('fanned out event', {
    event: msg.event,
    id: msg.id,
    status: msg.status,
    // Correlation id of the transaction-service request that caused this emit
    // (set by that service's RequestIdFilter, carried in the event payload).
    // May be null/undefined for events emitted outside a request scope.
    requestId: msg.requestId,
    rooms,
  });
}

/**
 * Subscribe a DEDICATED redis client (separate from the adapter pub/sub pair)
 * to the events channel and wire it to the fan-out handler.
 *
 * @param {import('socket.io').Server} io
 * @param {import('ioredis').Redis} subClient - dedicated subscriber client
 */
async function startFanout(io, subClient) {
  subClient.on('message', (channel, raw) => {
    if (channel !== config.eventsChannel) return;
    handleMessage(io, raw);
  });

  await subClient.subscribe(config.eventsChannel);
  logger.info('subscribed to events channel', { channel: config.eventsChannel });
}

module.exports = { startFanout, handleMessage, targetRooms };
