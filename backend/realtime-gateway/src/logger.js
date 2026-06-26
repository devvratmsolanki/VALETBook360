'use strict';

/**
 * Tiny structured logger. One JSON line per event so the output is
 * grep-able and ships cleanly to any log aggregator. No external deps.
 */

function emit(level, msg, fields) {
  const line = {
    ts: new Date().toISOString(),
    level,
    msg,
    ...(fields || {}),
  };
  // info/debug/warn -> stdout, error -> stderr.
  const out = level === 'error' ? process.stderr : process.stdout;
  out.write(JSON.stringify(line) + '\n');
}

module.exports = {
  info: (msg, fields) => emit('info', msg, fields),
  warn: (msg, fields) => emit('warn', msg, fields),
  error: (msg, fields) => emit('error', msg, fields),
  debug: (msg, fields) => emit('debug', msg, fields),
};
