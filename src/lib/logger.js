// Dev-only structured logger. In production builds (import.meta.env.PROD)
// debug/info/warn become no-ops so we don't leak [Auth] / [WhatsApp] /
// [Notifications] noise to end-user devtools. Errors always log so crash
// diagnostics survive in production consoles.
//
// Use this instead of bare console.log in app code. Direct console.error
// calls are still acceptable for hard failures.

const isDev = import.meta.env.DEV;

const noop = () => { };

export const logger = {
    debug: isDev ? console.debug.bind(console) : noop,
    info: isDev ? console.info.bind(console) : noop,
    log: isDev ? console.log.bind(console) : noop,
    warn: isDev ? console.warn.bind(console) : noop,
    // Errors always log — they're load-bearing for triage.
    error: console.error.bind(console),
};

export default logger;
