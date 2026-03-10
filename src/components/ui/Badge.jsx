import { cn, getStatusColor } from '../../lib/utils';

const Badge = ({ children, variant, className }) => {
    return (
        <span
            className={cn(
                'inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-medium capitalize',
                variant ? getStatusColor(variant) : 'bg-dark-600 text-gray-400 border-white/10',
                className
            )}
        >
            {children}
        </span>
    );
};

export default Badge;
