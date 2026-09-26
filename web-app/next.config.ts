import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  poweredByHeader: false,
  devIndicators: false,
  // The Arena preview iframe uses a per-session subdomain for Next.js dev assets/HMR.
  allowedDevOrigins: ["*.e2b.app"],
};

export default nextConfig;
