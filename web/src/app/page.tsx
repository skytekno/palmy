'use client';
import dynamic from 'next/dynamic';

const PalmyApp = dynamic(() => import('@/components/PalmyApp'), {
  ssr: false,
  loading: () => <main className="initial-loading" aria-live="polite">Menyiapkan Palmy…</main>,
});
export default function Page() { return <PalmyApp />; }
