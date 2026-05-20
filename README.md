# 🚗 ValetPro 360

A premium, end-to-end Valet Management System designed to streamline parking operations, enhance driver performance, and provide real-time analytics for companies. Built with speed, security, and scalability in mind.

---

## ✨ Core Features

### 👤 User Roles
-   **Super Admin**: Full visibility and control over all companies, system users, global transactions, and integration logs.
-   **Company Manager**: Dedicated dashboard for company owners to manage multiple locations, track driver performance, handle staff, and oversee contracts.
-   **Valet Operator**: Streamlined terminal for real-time car parking and retrieval at specific locations.
-   **Driver**: Mobile-friendly panel for drivers to manage tasks on the web or via the companion **Flutter Mobile App**.

### 🛠 Key Functionalities
-   **Real-time Dashboard**: Live monitoring of parking transactions and occupancy.
-   **QR Code Integration**: Instant car check-in/out via QR codes for a touchless experience.
-   **Advanced Analytics**: Deep insights into driver efficiency and location performance.
-   **WhatsApp Integration**: Automated notifications for customers and staff (enabled via feature flag).
-   **Role-Based Access Control**: Secure, multi-tiered access system powered by Supabase Auth.
-   **Multi-Location Management**: Scalable architecture supporting unlimited parking locations per company.

---

## 🚀 Tech Stack

-   **Frontend**: [React 19](https://react.dev/) + [Vite](https://vitejs.dev/)
-   **Styling**: [Tailwind CSS 4](https://tailwindcss.com/)
-   **Database & Auth**: [Supabase](https://supabase.com/)
-   **Icons**: [Lucide React](https://lucide.dev/)
-   **Networking**: [Axios](https://axios-http.com/)
-   **Utility**: [QR Code](https://www.npmjs.com/package/qrcode), [clsx](https://www.npmjs.com/package/clsx), [tailwind-merge](https://www.npmjs.com/package/tailwind-merge)

---

## 🛠 Getting Started

### Prerequisites
-   Node.js (v18 or higher)
-   npm or yarn
-   Supabase Account

### Installation

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/your-username/valetpro-360.git
    cd valetpro-360
    ```

2.  **Install dependencies:**
    ```bash
    npm install
    ```

3.  **Environment Setup:**
    Create a `.env` file in the root directory based on `.env.example`:
    ```env
    VITE_SUPABASE_URL=your_supabase_url
    VITE_SUPABASE_ANON_KEY=your_supabase_anon_key
    VITE_ENABLE_WHATSAPP=true
    VITE_N8N_WEBHOOK_URL=your_n8n_webhook_url
    ```

4.  **Start the development server:**
    ```bash
    npm run dev
    ```

---

## 📁 Project Structure

```text
valetpro3/
├── src/
│   ├── components/       # Reusable UI components
│   ├── contexts/         # Auth and Theme providers
│   ├── lib/              # Supabase client and utilities
│   ├── pages/            # Role-specific pages (Admin, Company, Operator, Driver)
│   ├── hooks/            # Custom React hooks
│   └── App.jsx           # Main routing configuration
├── supabase/             # Database migrations and seed files
├── public/               # Static assets
└── tailwind.config.js    # Styling configuration
```

---

## 🛡 License

This project is proprietary and confidential.

---

## 👨‍💻 Developed By

**Devvrat Solanki**
Driven by efficiency and innovation in valet management solutions.
