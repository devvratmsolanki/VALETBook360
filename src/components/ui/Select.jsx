import { cn } from '../../lib/utils';
import { ChevronDown } from 'lucide-react';

const Select = ({ label, options = [], error, className, ...props }) => {
    return (
        <div className="space-y-1.5">
            {label && (
                <label className="block text-sm font-medium text-gray-300" htmlFor={props.id}>
                    {label}
                </label>
            )}
            <div className="relative">
                <select
                    className={cn(
                        'block w-full appearance-none rounded-xl border-0 bg-dark-600 py-3 pl-4 pr-10 text-gray-200 shadow-sm ring-1 ring-inset ring-white/5 focus:ring-2 focus:ring-brand-500/50 sm:text-sm transition-all duration-300',
                        error && 'ring-red-500/50',
                        className
                    )}
                    {...props}
                >
                    {options.map((opt) => (
                        <option key={opt.value} value={opt.value}>{opt.label}</option>
                    ))}
                </select>
                <ChevronDown className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-500" />
            </div>
            {error && <p className="text-xs text-red-400">{error}</p>}
        </div>
    );
};

export default Select;
