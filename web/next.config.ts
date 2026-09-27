import type { NextConfig } from 'next';
import { fileURLToPath } from 'node:url';
const config: NextConfig = {
  output: 'export',
  turbopack: { root: fileURLToPath(new URL('.', import.meta.url)) },
  poweredByHeader: false,
  reactStrictMode: true,
  images: { unoptimized: true },
};
export default config;
