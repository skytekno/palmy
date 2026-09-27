import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Palmy — Ruang tenang untuk keuanganmu',
  description: 'Kelola keuangan dengan profil yang dienkripsi di perangkatmu.',
  robots: { index: false, follow: false },
  referrer: 'no-referrer',
};
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="id"><body>{children}</body></html>;
}
