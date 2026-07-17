import type { Metadata } from "next";
import Link from "next/link";

/* eslint-disable @next/next/no-img-element -- local product assets are intentionally served directly */

const downloadUrl = "/downloads/Shakespeare-latest.zip";

export const metadata: Metadata = {
  title: "How Shakespeare works",
  description: "A simple, private writing workflow for your Mac.",
  alternates: { canonical: "/how-it-works" },
  openGraph: {
    title: "How Shakespeare works",
    description: "A simple, private writing workflow for your Mac.",
    url: "/how-it-works",
  },
};

export default function HowItWorks() {
  return (
    <main className="landing how-landing">
      <a className="skip-link" href="#main-content">Skip to content</a>

      <header className="site-header">
        <Link className="brand" href="/" aria-label="Shakespeare home">
          <img src="/app-icon.png" alt="" />
          <span>Shakespeare.</span>
        </Link>

        <nav className="header-actions" aria-label="Primary navigation">
          <span className="release-note"><i aria-hidden="true" /> Beta for macOS 14+</span>
          <Link className="header-link active" href="/how-it-works" aria-current="page">How it works</Link>
          <a className="header-download" href={downloadUrl} download>
            Download <span aria-hidden="true">↓</span>
          </a>
        </nav>
      </header>

      <section className="hero how-simple-hero" id="main-content">
        <div className="hero-copy how-simple-copy">
          <p className="eyebrow"><span aria-hidden="true">✦</span> How it works</p>
          <h1>Help when you ask.<br /><em>Your voice when you write.</em></h1>
          <p className="hero-lede how-story">
            Download Shakespeare and open it like any Mac app. Your documents,
            versions, and style data stay on your Mac. When you want revision,
            optional grammar checks, or source-linked research, connect one
            OpenRouter key—validated first, then stored in Keychain. Keep style
            learning on, turn it off, or add a few samples; every preference
            remains yours to review.
          </p>

          <div className="how-flow" aria-label="Shakespeare workflow">
            <span><i>01</i> Install</span>
            <span><i>02</i> Connect when ready</span>
            <span><i>03</i> Write</span>
          </div>

          <div className="hero-actions">
            <a className="primary-button" href={downloadUrl} download>
              <span>Download for Mac</span>
              <span className="button-icon" aria-hidden="true">↓</span>
            </a>
            <Link className="text-link" href="/">Back home <span aria-hidden="true">↖</span></Link>
          </div>
        </div>

        <div className="product-stage">
          <div className="stage-glow" aria-hidden="true" />
          <div className="product-label">
            <span><i aria-hidden="true" /> Actual app</span>
            <span>Shakespeare for macOS</span>
          </div>
          <figure className="product-window">
            <img
              src="/shakespeare-editor.jpg"
              width="1131"
              height="701"
              alt="The real Shakespeare editor showing an essay"
              fetchPriority="high"
            />
          </figure>
          <div className="privacy-card">
            <span className="privacy-icon" aria-hidden="true">◆</span>
            <span><strong>Local-first</strong><small>Your work stays yours.</small></span>
          </div>
          <p className="first-launch">One optional OpenRouter key powers writing help and cited research.</p>
        </div>
      </section>
    </main>
  );
}
