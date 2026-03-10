import { cn } from '../../lib/utils';

const Input = ({ icon: Icon, label, error, className, ...props }) => {
    return (
        <div className="space-y-1.5">
            {label && (
                <label className="block text-sm font-medium text-gray-300" htmlFor={props.id}>
                    {label}
                </label>
            )}
            <div className="relative group">
                {Icon && (
                    <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3.5">
                        <Icon className="h-4 w-4 text-gray-500 group-focus-within:text-brand-500 transition-colors" />
                    </div>
                )}
                <input
                    className={cn(
                        'block w-full rounded-xl border-0 bg-dark-600 py-3 text-gray-200 placeholder:text-gray-500 shadow-sm ring-1 ring-inset ring-white/5 focus:ring-2 focus:ring-brand-500/50 sm:text-sm transition-all duration-300',
                        Icon ? 'pl-10 pr-4' : 'px-4',
                        error && 'ring-red-500/50',
                        className
                    )}
                    {...props}
                />
            </div>
            {error && <p className="text-xs text-red-400">{error}</p>}
        </div>
    );
};

export default Input;
