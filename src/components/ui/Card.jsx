import { cn } from '../../lib/utils';

const Card = ({ children, className, glow, ...props }) => {
    return (
        <div className={cn('glass-card', glow && 'brand-glow', className)} {...props}>
            {children}
        </div>
    );
};

export default Card;
