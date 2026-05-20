import { Component } from 'react';
import { AlertTriangle, RefreshCw } from 'lucide-react';
import logger from '../../lib/logger';

// A render throw inside any deep component would otherwise crash the whole
// SPA to a white screen with no way to recover. This boundary catches the
// throw, logs it, and shows a recoverable fallback. Use one boundary at the
// app root (for catastrophic failures) and one inside Layout (so a single
// page failing doesn't kill the sidebar/header/navigation).
class ErrorBoundary extends Component {
    constructor(props) {
        super(props);
        this.state = { error: null };
    }

    static getDerivedStateFromError(error) {
        return { error };
    }

    componentDidCatch(error, info) {
        logger.error('[ErrorBoundary]', error, info?.componentStack);
    }

    handleReset = () => {
        this.setState({ error: null });
        if (this.props.onReset) this.props.onReset();
    };

    handleReload = () => {
        window.location.reload();
    };

    render() {
        if (!this.state.error) return this.props.children;

        if (this.props.fallback) {
            return this.props.fallback(this.state.error, this.handleReset);
        }

        const level = this.props.level || 'app';
        const message = this.state.error?.message || 'An unexpected error occurred';

        return (
            <div className={level === 'app' ? 'min-h-screen bg-dark-900 flex items-center justify-center p-6' : 'flex items-center justify-center p-12'}>
                <div className="max-w-md w-full bg-dark-800 border border-red-500/20 rounded-2xl p-6 text-center">
                    <div className="bg-red-500/10 h-14 w-14 rounded-full flex items-center justify-center mx-auto mb-4">
                        <AlertTriangle className="h-7 w-7 text-red-400" />
                    </div>
                    <h2 className="text-lg font-semibold text-white mb-1">Something went wrong</h2>
                    <p className="text-sm text-gray-400 mb-5 break-words">{message}</p>
                    <div className="flex gap-2 justify-center">
                        <button
                            onClick={this.handleReset}
                            className="inline-flex items-center gap-2 px-4 py-2 rounded-xl bg-brand-500/10 text-brand-400 border border-brand-500/20 hover:bg-brand-500/20 text-sm font-medium transition-all"
                        >
                            <RefreshCw className="h-3.5 w-3.5" /> Try again
                        </button>
                        {level === 'app' && (
                            <button
                                onClick={this.handleReload}
                                className="inline-flex items-center gap-2 px-4 py-2 rounded-xl bg-white/5 text-gray-300 hover:bg-white/10 text-sm font-medium transition-all"
                            >
                                Reload page
                            </button>
                        )}
                    </div>
                </div>
            </div>
        );
    }
}

export default ErrorBoundary;
