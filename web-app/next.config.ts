import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Bundle the Next.js server and its traced dependencies inside the desktop
  // installers. No deployed/Vercel URL is needed at runtime.
  output: "standalone",
  poweredByHeader: false,
  devIndicators: false,
  // The Arena preview iframe uses a per-session subdomain for Next.js dev assets/HMR.
  allowedDevOrigins: ["*.e2b.app"],
};

export default nextConfig;
