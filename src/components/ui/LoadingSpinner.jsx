import React from 'react';

const LoadingSpinner = ({ size = 'md', color = 'brand', className = '' }) => {
    const sizeClasses = {
        sm: 'h-4 w-4',
        md: 'h-6 w-6',
        lg: 'h-10 w-10',
    };

    const colorClasses = {
        brand: 'border-brand-500',
        white: 'border-white',
        emerald: 'border-emerald-500',
    };

    return (
        <div className={`animate-spin rounded-full border-2 border-t-transparent ${sizeClasses[size]} ${colorClasses[color]} ${className}`} />
    );
};

export default LoadingSpinner;
