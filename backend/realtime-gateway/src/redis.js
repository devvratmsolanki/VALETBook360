'use strict';

const Redis = require('ioredis');
const config = require('./config');
const logger = require('./logger');

/**
 * Build a single ioredis client with bounded exponential backoff. We never
 * give up retrying (a transient Redis outage should heal, not crash-loop the
 * gateway), but we log clearly so the failure is never silent.
 *
 * @param {string} role - human label for logs (e.g. "adapter-pub").
 */
function createClient(role) {
  const client = new Redis({
    host: config.redisHost,
    port: config.redisPort,
    // Exponential-ish backoff capped at 10s between attempts.
    retryStrategy(times) {
      const delay = Math.min(times * 200, 10000);
      logger.warn('redis reconnecting', { role, attempt: times, delayMs: delay });
      return delay;
    },
    // Keep buffering commands while disconnected rather than throwing.
    enableOfflineQueue: true,
    maxRetriesPerRequest: null,
    lazyConnect: false,
  });

  client.on('connect', () => logger.info('redis connected', { role }));
  client.on('ready', () => logger.info('redis ready', { role }));
  client.on('end', () => logger.warn('redis connection ended', { role }));
  client.on('error', (err) =>
    logger.error('redis error', { role, error: err.message }),
  );

  return client;
}

module.exports = { createClient };
