import type { Metadata, Viewport } from "next";
import { Inter, Plus_Jakarta_Sans } from "next/font/google";

import "./globals.css";

// The app's pairing, from `AppTheme.theme`: Plus Jakarta Sans for headings,
// Inter for everything else.
const display = Plus_Jakarta_Sans({
  subsets: ["latin"],
  weight: ["600", "700"],
  variable: "--font-display",
});

const body = Inter({
  subsets: ["latin"],
  variable: "--font-body",
});

export const metadata: Metadata = {
  title: "Massar",
  description: "Plan a route through Algeria, and follow it stop by stop.",
};

export const viewport: Viewport = {
  // The deep navy the route screens start on, so the browser chrome does not
  // sit as a pale band above a dark header.
  themeColor: "#14254a",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={`${display.variable} ${body.variable}`}>
      <body>{children}</body>
    </html>
  );
}
