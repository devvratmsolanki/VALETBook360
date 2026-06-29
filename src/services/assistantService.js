import { supabase } from '../lib/supabase';

// Calls the JWT-protected `assistant-chat` edge function. The Anthropic API key
// never touches the browser — the edge function holds it and derives the user's
// role server-side. `history` is the prior turns ([{role, content}]); `message`
// is the new user message. Returns the assistant's reply string.
export const askAssistant = async (history, message) => {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session) throw new Error('You need to be signed in to use the assistant.');

    const messages = [
        ...history.map((m) => ({ role: m.role, content: m.content })),
        { role: 'user', content: message },
    ];

    const response = await fetch(
        `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/assistant-chat`,
        {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                Authorization: `Bearer ${session.access_token}`,
            },
            body: JSON.stringify({ messages }),
        },
    );

    const result = await response.json().catch(() => ({}));
    if (!response.ok) {
        throw new Error(result.error || 'The assistant is unavailable right now.');
    }
    return result.reply;
};
