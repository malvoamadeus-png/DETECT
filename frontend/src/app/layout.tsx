import type { Metadata } from "next";

import "./globals.css";

export const metadata: Metadata = {
  title: "DETECT",
  description: "Permissionless token recipient intelligence"
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}

