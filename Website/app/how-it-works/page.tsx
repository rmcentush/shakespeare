import type { Metadata } from "next";
import Link from "next/link";

/* eslint-disable @next/next/no-img-element -- local product assets are intentionally served directly */

const downloadUrl = "/downloads/Shakespeare-latest.zip";

export const metadata: Metadata = {
  title: "How Shakespeare works",
  description: "Install Shakespeare, connect writing help, and start writing in your own voice.",
  alternates: { canonical: "/how-it-works" },
  openGraph: {
    title: "How Shakespeare works",
    description: "Three steps to a quieter way to write.",
    url: "/how-it-works",
  },
};

const setupSteps = [
  {
    number: "01",
    label: "Install",
    title: "Add it to Applications.",
    body: "Unzip Shakespeare, move it to Applications, then right-click and choose Open once.",
    note: "macOS 14+ · Apple silicon and Intel",
  },
  {
    number: "02",
    label: "Connect",
    title: "Paste one OpenRouter key.",
    body: "This powers writing help and research. The key is validated, then stored in macOS Keychain.",
    note: "Get an OpenRouter key",
  },
  {
    number: "03",
    label: "Personalize",
    title: "Choose what it learns.",
    body: "Keep style learning on, turn it off, or add a few text samples. Every preference stays reviewable.",
    note: "Pause or clear it at any time",
  },
];

const features = [
  { mark: "¶", title: "Write", body: "A quiet native editor with recovery drafts, versions, and focus mode." },
  { mark: "✦", title: "Revise", body: "Sharpen selected passages without giving up control of the sentence." },
  { mark: "✓", title: "Proof", body: "Use local spelling and optional, paragraph-scoped AI grammar checks." },
  { mark: "↗", title: "Research", body: "Get current, linked answers beside the draft—not inside your style profile." },
];

export default function HowItWorks() {
  return (
    <main className="how-page">
      <a className="skip-link" href="#main-content">Skip to content</a>

      <header className="site-header how-header">
        <Link className="brand" href="/" aria-label="Shakespeare home">
          <img src="/app-icon.png" alt="" />
          <span>Shakespeare.</span>
        </Link>
        <nav className="header-actions" aria-label="Primary navigation">
          <Link className="header-link" href="/">Home</Link>
          <Link className="header-link active" href="/how-it-works" aria-current="page">How it works</Link>
          <a className="header-download" href={downloadUrl} download>
            Download <span aria-hidden="true">↓</span>
          </a>
        </nav>
      </header>

      <section className="how-hero concise" id="main-content">
        <div className="how-hero-copy">
          <p className="eyebrow"><span aria-hidden="true">✦</span> How it works</p>
          <h1>Set up once.<br /><em>Stay in the sentence.</em></h1>
          <p>
            Start with the editor. Connect one model account when you want help,
            then decide what Shakespeare may learn.
          </p>
        </div>

        <figure className="how-product-frame">
          <div className="how-product-label">
            <span><i aria-hidden="true" /> The real Shakespeare editor</span>
            <span>macOS</span>
          </div>
          <img
            src="/shakespeare-editor.jpg"
            width="1131"
            height="701"
            alt="Shakespeare's editor showing a formatted essay"
          />
        </figure>
      </section>

      <section className="how-section setup-section concise-section" aria-labelledby="setup-title">
        <div className="how-section-heading">
          <p className="eyebrow"><span aria-hidden="true">✦</span> Start here</p>
          <h2 id="setup-title">Three steps.<br /><em>About five minutes.</em></h2>
          <p>The model connection is optional; the editor works without it.</p>
        </div>

        <ol className="setup-grid concise-grid">
          {setupSteps.map((step) => (
            <li className="setup-card" key={step.number}>
              <div className="setup-card-top">
                <span className="setup-number">{step.number}</span>
                <span className="setup-label">{step.label}</span>
              </div>
              <h3>{step.title}</h3>
              <p>{step.body}</p>
              {step.number === "02" ? (
                <a className="setup-note setup-note-link" href="https://openrouter.ai/settings/keys">
                  {step.note} <span aria-hidden="true">↗</span>
                </a>
              ) : (
                <span className="setup-note">{step.note}</span>
              )}
            </li>
          ))}
        </ol>
      </section>

      <section className="how-section features-section concise-section" aria-labelledby="features-title">
        <div className="how-section-heading compact">
          <p className="eyebrow"><span aria-hidden="true">✦</span> Inside the app</p>
          <h2 id="features-title">Four tools.<br /><em>One writing room.</em></h2>
        </div>

        <div className="how-feature-grid concise-features">
          {features.map((feature) => (
            <article className="how-feature" key={feature.title}>
              <span className="feature-mark" aria-hidden="true">{feature.mark}</span>
              <h3>{feature.title}</h3>
              <p>{feature.body}</p>
            </article>
          ))}
        </div>
      </section>

      <aside className="how-summary" aria-label="Privacy and download">
        <div>
          <p className="eyebrow light"><span aria-hidden="true">◆</span> Private by design</p>
          <h2>Your documents and style data stay on your Mac.</h2>
          <p>Only the excerpt needed for a model-powered action is sent, with provider data collection disabled.</p>
        </div>
        <a className="button-light" href={downloadUrl} download>
          <span>Download for Mac</span><span aria-hidden="true">↓</span>
        </a>
      </aside>

      <footer className="how-footer">
        <Link className="brand" href="/">
          <img src="/app-icon.png" alt="" />
          <span>Shakespeare.</span>
        </Link>
        <p>Made for writers who still want to sound human.</p>
        <a href={`${downloadUrl}.sha256`} download>SHA-256 checksum</a>
      </footer>
    </main>
  );
}
