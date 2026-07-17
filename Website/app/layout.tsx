import type { Metadata } from "next";
import { Cormorant_Garamond, Manrope } from "next/font/google";
import "./globals.css";

const serif = Cormorant_Garamond({
  variable: "--font-serif",
  subsets: ["latin"],
  weight: ["400", "500", "600"],
});

const sans = Manrope({
  variable: "--font-sans",
  subsets: ["latin"],
});

const title = "Shakespeare — Write like yourself, only sharper";
const description =
  "A calm, local-first writing app for macOS with thoughtful revision, private style learning, and source-backed research.";

export const metadata: Metadata = {
  metadataBase: new URL("https://writeshakespeare.com"),
  title,
  description,
  alternates: { canonical: "/" },
  icons: {
    icon: "/app-icon.png",
    apple: "/app-icon.png",
  },
  openGraph: {
    type: "website",
    title,
    description,
    images: [{ url: "/og-v5.png", width: 1732, height: 908, alt: "Write like yourself. Shakespeare." }],
  },
  twitter: {
    card: "summary_large_image",
    title,
    description,
    images: ["/og-v5.png"],
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className={`${serif.variable} ${sans.variable}`}>{children}</body>
    </html>
  );
}
