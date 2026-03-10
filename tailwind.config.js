/** @type {import('tailwindcss').Config} */
export default {
    content: [
        "./index.html",
        "./src/**/*.{js,ts,jsx,tsx}",
    ],
    darkMode: 'class',
    theme: {
        extend: {
            fontFamily: {
                sans: ['Inter', 'system-ui', 'sans-serif'],
                serif: ['"Playfair Display"', 'Georgia', 'serif'],
            },
            colors: {
                brand: {
                    300: '#E84A7A',
                    400: '#D42862',
                    500: '#A60445',
                    600: '#8A0339',
                    700: '#6E032E',
                    900: '#3A0119',
                },
                dark: {
                    950: '#030303',
                    900: '#050505',
                    800: '#0F0F0F',
                    700: '#1A1A1A',
                    600: '#2A2A2A',
                    500: '#3A3A3A',
                }
            },
            animation: {
                'fade-in': 'fadeIn 0.5s ease-out',
                'slide-up': 'slideUp 0.3s ease-out',
                'pulse-brand': 'pulseBrand 2s infinite',
            },
            keyframes: {
                fadeIn: {
                    '0%': { opacity: '0' },
                    '100%': { opacity: '1' },
                },
                slideUp: {
                    '0%': { opacity: '0', transform: 'translateY(10px)' },
                    '100%': { opacity: '1', transform: 'translateY(0)' },
                },
                pulseBrand: {
                    '0%, 100%': { boxShadow: '0 0 0 0 rgba(166, 4, 69, 0.15)' },
                    '50%': { boxShadow: '0 0 0 8px rgba(166, 4, 69, 0)' },
                },
            },
        },
    },
    plugins: [],
}
