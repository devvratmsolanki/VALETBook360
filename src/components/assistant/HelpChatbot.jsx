import { useState, useRef, useEffect } from 'react';
import { MessageCircle, X, Send, Sparkles } from 'lucide-react';
import { cn } from '../../lib/utils';
import { askAssistant } from '../../services/assistantService';
import { useAuth } from '../../contexts/AuthContext';
import logger from '../../lib/logger';

// Floating, role-aware help assistant. Mounted once in Layout so it's available
// on every authenticated screen. The Anthropic key stays server-side (the
// assistant-chat edge function); this component only sends/receives text.
const HelpChatbot = () => {
    const { role } = useAuth();
    const [open, setOpen] = useState(false);
    const [messages, setMessages] = useState([]); // {role:'user'|'assistant', content}
    const [input, setInput] = useState('');
    const [busy, setBusy] = useState(false);
    const [error, setError] = useState(null);
    const scrollRef = useRef(null);
    const inputRef = useRef(null);

    useEffect(() => {
        if (open && scrollRef.current) {
            scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
        }
    }, [messages, open, busy]);

    useEffect(() => {
        if (open) inputRef.current?.focus();
    }, [open]);

    const send = async () => {
        const text = input.trim();
        if (!text || busy) return;
        setError(null);
        const history = messages;
        setMessages((m) => [...m, { role: 'user', content: text }]);
        setInput('');
        setBusy(true);
        try {
            const reply = await askAssistant(history, text);
            setMessages((m) => [...m, { role: 'assistant', content: reply }]);
        } catch (err) {
            logger.error('assistant error', err);
            setError(err.message || 'The assistant is unavailable right now.');
        } finally {
            setBusy(false);
        }
    };

    const onKeyDown = (e) => {
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            send();
        }
    };

    const suggestions = [
        'How do I check in a car?',
        'How do key slots work?',
        'How do I add a driver?',
    ];

    return (
        <>
            {/* Launcher */}
            <button
                type="button"
                onClick={() => setOpen((v) => !v)}
                aria-label={open ? 'Close help assistant' : 'Open help assistant'}
                className={cn(
                    'fixed bottom-5 right-5 z-50 flex h-14 w-14 items-center justify-center rounded-full',
                    'bg-brand-500 text-white shadow-lg shadow-brand-500/30 transition-all hover:scale-105 hover:bg-brand-600',
                    'focus:outline-none focus:ring-2 focus:ring-brand-400 focus:ring-offset-2 focus:ring-offset-dark-900',
                )}
            >
                {open ? <X className="h-6 w-6" /> : <MessageCircle className="h-6 w-6" />}
            </button>

            {/* Panel */}
            {open && (
                <div
                    role="dialog"
                    aria-label="Help assistant"
                    className={cn(
                        'fixed z-50 flex flex-col overflow-hidden rounded-2xl border border-white/10 bg-dark-800 shadow-2xl',
                        'bottom-24 right-5 w-[min(24rem,calc(100vw-2.5rem))] h-[min(34rem,calc(100vh-8rem))]',
                    )}
                >
                    {/* Header */}
                    <div className="flex items-center gap-2 border-b border-white/10 bg-dark-700/60 px-4 py-3">
                        <span className="flex h-8 w-8 items-center justify-center rounded-full bg-brand-500/15 text-brand-400">
                            <Sparkles className="h-4 w-4" />
                        </span>
                        <div className="min-w-0">
                            <p className="text-sm font-semibold text-white">LogBook360 Assistant</p>
                            <p className="truncate text-[11px] text-gray-400">Ask anything about using the app</p>
                        </div>
                    </div>

                    {/* Messages */}
                    <div ref={scrollRef} className="flex-1 space-y-3 overflow-y-auto px-4 py-4">
                        {messages.length === 0 && (
                            <div className="space-y-3">
                                <p className="text-sm text-gray-300">
                                    Hi{role ? ` (${role})` : ''}! I can help you use LogBook360. Try:
                                </p>
                                <div className="flex flex-col gap-2">
                                    {suggestions.map((s) => (
                                        <button
                                            key={s}
                                            type="button"
                                            onClick={() => { setInput(s); inputRef.current?.focus(); }}
                                            className="rounded-lg border border-white/10 bg-dark-700/50 px-3 py-2 text-left text-xs text-gray-300 transition-colors hover:border-brand-500/40 hover:text-brand-300"
                                        >
                                            {s}
                                        </button>
                                    ))}
                                </div>
                            </div>
                        )}

                        {messages.map((m, i) => (
                            <div
                                key={i}
                                className={cn('flex', m.role === 'user' ? 'justify-end' : 'justify-start')}
                            >
                                <div
                                    className={cn(
                                        'max-w-[85%] whitespace-pre-wrap rounded-2xl px-3 py-2 text-sm',
                                        m.role === 'user'
                                            ? 'bg-brand-500 text-white rounded-br-sm'
                                            : 'bg-dark-700 text-gray-200 rounded-bl-sm',
                                    )}
                                >
                                    {m.content}
                                </div>
                            </div>
                        ))}

                        {busy && (
                            <div className="flex justify-start">
                                <div className="flex items-center gap-1 rounded-2xl rounded-bl-sm bg-dark-700 px-3 py-2.5">
                                    <span className="h-2 w-2 animate-bounce rounded-full bg-gray-400 [animation-delay:-0.3s]" />
                                    <span className="h-2 w-2 animate-bounce rounded-full bg-gray-400 [animation-delay:-0.15s]" />
                                    <span className="h-2 w-2 animate-bounce rounded-full bg-gray-400" />
                                </div>
                            </div>
                        )}

                        {error && <p className="text-xs text-red-400">{error}</p>}
                    </div>

                    {/* Composer */}
                    <div className="border-t border-white/10 bg-dark-700/40 p-3">
                        <div className="flex items-end gap-2">
                            <textarea
                                ref={inputRef}
                                value={input}
                                onChange={(e) => setInput(e.target.value)}
                                onKeyDown={onKeyDown}
                                rows={1}
                                placeholder="Ask a question…"
                                aria-label="Message the assistant"
                                className="max-h-28 flex-1 resize-none rounded-xl border-0 bg-dark-600 px-3 py-2 text-sm text-gray-200 placeholder:text-gray-500 ring-1 ring-white/5 focus:outline-none focus:ring-2 focus:ring-brand-500/50"
                            />
                            <button
                                type="button"
                                onClick={send}
                                disabled={busy || !input.trim()}
                                aria-label="Send message"
                                className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-brand-500 text-white transition-colors hover:bg-brand-600 disabled:opacity-40"
                            >
                                <Send className="h-4 w-4" />
                            </button>
                        </div>
                        <p className="mt-1.5 px-1 text-[10px] text-gray-500">AI can make mistakes — verify important steps.</p>
                    </div>
                </div>
            )}
        </>
    );
};

export default HelpChatbot;
