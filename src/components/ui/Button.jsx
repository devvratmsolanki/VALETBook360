import { cn } from '../../lib/utils';

const variants = {
    primary: 'brand-gradient text-black font-semibold shadow-lg shadow-brand-900/20 hover:from-brand-300 hover:to-brand-500',
    outline: 'border border-brand-500/30 text-brand-400 hover:bg-brand-500/10 bg-transparent',
    ghost: 'text-gray-400 hover:text-white hover:bg-white/5 bg-transparent',
    destructive: 'bg-red-500/10 text-red-400 border border-red-500/20 hover:bg-red-500/20',
};

const sizes = {
    sm: 'px-3 py-1.5 text-xs rounded-lg',
    md: 'px-4 py-2.5 text-sm rounded-lg',
    lg: 'px-6 py-3.5 text-base rounded-xl',
};

const Button = ({ children, variant = 'primary', size = 'md', className, disabled, ...props }) => {
    return (
        <button
            className={cn(
                'inline-flex items-center justify-center gap-2 font-medium transition-all duration-300 transform active:scale-[0.98] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-500 disabled:opacity-50 disabled:cursor-not-allowed',
                variants[variant],
                sizes[size],
                className
            )}
            disabled={disabled}
            {...props}
        >
            {children}
        </button>
    );
};

export default Button;
