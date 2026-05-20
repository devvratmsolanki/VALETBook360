// ServiceError gives the service layer a stable error shape:
//   - `userMessage` is safe to show in a toast (already user-friendly)
//   - `cause` keeps the original Supabase/Fetch error for logging
//   - `code` is the optional underlying error code (e.g. Postgres PGRST116)
//
// Components catching errors from services should prefer
// `toast.error(err.userMessage || err.message)` so we always show a real
// reason instead of a generic "Failed to ..." string.

export class ServiceError extends Error {
    constructor(userMessage, { cause, code } = {}) {
        super(userMessage);
        this.name = 'ServiceError';
        this.userMessage = userMessage;
        this.cause = cause;
        if (code) this.code = code;
    }
}

// Map common Supabase / Postgres error codes to user-readable messages.
// Anything not mapped falls through to `error.message` or the supplied
// default — services should set the default to a verb-noun ("Failed to load
// drivers") so the user knows what action failed even when the cause is
// opaque.
const FRIENDLY_CODES = {
    '23505': 'That value is already in use.',
    '23503': 'Cannot complete this action — related records exist.',
    '42501': 'You don\'t have permission to do that.',
    'PGRST116': 'Record not found.',
};

export const wrapError = (err, defaultMessage = 'Something went wrong') => {
    if (err instanceof ServiceError) return err;
    const code = err?.code || err?.details?.code;
    const friendly = code && FRIENDLY_CODES[code];
    const message = friendly || err?.message || defaultMessage;
    return new ServiceError(message, { cause: err, code });
};
