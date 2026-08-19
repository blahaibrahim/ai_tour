import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  async rewrites() {
    return [
      {
        source: "/api/:path*",
        destination: `${process.env.NEXT_PUBLIC_API_URL || "http://localhost:8000"}/api/:path*`,
      },
    ];
  },

  async headers() {
    return [
      {
        /*
         * The Android build the landing page hands over.
         *
         * Next serves `public/` with a type guessed from the extension, and an
         * `.apk` it does not recognise goes out as `application/octet-stream`
         * — which some Android browsers will not offer to the package
         * installer. Naming the type and the disposition here means the file
         * arrives as an installable download rather than as a blob the
         * browser has to guess about.
         */
        source: "/app-release.apk",
        headers: [
          {
            key: "Content-Type",
            value: "application/vnd.android.package-archive",
          },
          {
            key: "Content-Disposition",
            value: 'attachment; filename="massar.apk"',
          },
        ],
      },
    ];
  },
};

export default nextConfig;
