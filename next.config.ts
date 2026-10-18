import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  reactCompiler: true,
  experimental: {
    staleTimes: { dynamic: 30, static: 180 },
  },
  poweredByHeader: false,
  allowedDevOrigins: ["10.159.135.109"],
  turbopack: {
    rules: {
      "*.css": {
        as: "*.css",
        loaders: ["@tailwindcss/turbopack"],
      },
    },
  },
};

export default nextConfig;
