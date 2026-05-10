import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

const root = dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  root,
  plugins: [react()],
  build: {
    rollupOptions: {
      input: resolve(root, "index.html"),
    },
  },
  server: {
    fs: {
      allow: [".."],
    },
    proxy: {
      "/grpc": {
        target: "http://localhost:8080",
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/grpc/, ""),
      },
    },
  },
});
