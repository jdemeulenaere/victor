import path from 'node:path';
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  root: process.cwd(),
  plugins: [react()],
  resolve: {
    alias: {
      '@bufbuild/protobuf': path.resolve(process.cwd(), 'node_modules/@bufbuild/protobuf/dist/esm'),
    },
  },
  server: {
    proxy: {
      '/grpc': {
        target: 'http://localhost:8080',
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/grpc/, ''),
      },
    },
  },
});
