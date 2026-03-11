import React, { useState, useEffect } from 'react';
import { UserCheck } from 'lucide-react';
import Select from '../ui/Select';
import { getDriversByCompany } from '../../services/driverService';

const DriverSelect = ({ companyId, value, onChange, label, required = false, error = '' }) => {
    const [drivers, setDrivers] = useState([]);
    const [loading, setLoading] = useState(false);

    useEffect(() => {
        if (!companyId) return;
        const fetchDrivers = async () => {
            setLoading(true);
            try {
                const list = await getDriversByCompany(companyId);
                setDrivers(list.filter(d => d.active));
            } catch (err) {
                console.error('[DriverSelect] Error fetching drivers:', err);
            } finally {
                setLoading(false);
            }
        };
        fetchDrivers();
    }, [companyId]);

    const options = [
        { value: '', label: loading ? 'Loading drivers...' : 'Select a driver...' },
        ...drivers.map(d => ({ value: d.id, label: d.staff_id ? `[${d.staff_id}] ${d.name}` : d.name }))
    ];

    return (
        <Select
            label={label || <span className="flex items-center gap-2"><UserCheck className="h-3.5 w-3.5 text-brand-500" /> Assigned Driver {required && <span className="text-red-400">*</span>}</span>}
            options={options}
            value={value}
            onChange={onChange}
            error={error}
        />
    );
};

export default DriverSelect;
