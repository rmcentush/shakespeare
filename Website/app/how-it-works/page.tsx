import type { Metadata } from "next";
import Link from "next/link";

/* eslint-disable @next/next/no-img-element -- local product assets are intentionally served directly */

const downloadUrl = "/downloads/Shakespeare-latest.zip";

export const metadata: Metadata = {
  title: "How Shakespeare works",
  description:
    "Set up Shakespeare, connect writing help, and learn how its private, local-first writing tools work.",
  alternates: { canonical: "/how-it-works" },
  openGraph: {
    title: "How Shakespeare works",
    description: "A five-minute setup for a quieter way to write.",
    url: "/how-it-works",
  },
};

const setupSteps = [
  {
    number: "01",
    label: "Install",
    title: "Put Shakespeare on your Mac.",
    body: "Download the ZIP, move Shakespeare to Applications, then right-click and choose Open on the first launch.",
    note: "macOS 14+ · Apple silicon and Intel",
  },
  {
    number: "02",
    label: "Connect",
    title: "Add one OpenRouter key.",
    body: "One connection powers revision, optional grammar help, style review, and cited web research. Shakespeare validates the key before saving it in macOS Keychain.",
    note: "The editor still works if you skip this step.",
  },
  {
    number: "03",
    label: "Personalize",
    title: "Choose what it learns.",
    body: "Keep private style learning on, turn it off, or add a few text or Markdown samples for a faster start. Every durable preference remains reviewable.",
    note: "Pause, edit, or clear personalization at any time.",
  },
];

const features = [
  {
    mark: "¶",
    title: "A real writing room",
    body: "Draft and format in a quiet native editor with recovery drafts, version history, focus mode, and document-level typography.",
  },
  {
    mark: "✦",
    title: "Revision in your voice",
    body: "Attach a passage, ask for a sharper version, and keep control of every change. Your meaning always outranks the model.",
  },
  {
    mark: "✓",
    title: "Proofing on your terms",
    body: "Use local macOS spelling by default. AI grammar checks are optional and limited to changed paragraphs after you pause.",
  },
  {
    mark: "↗",
    title: "Research beside the draft",
    body: "Ask current questions in the margin and receive linked answers. Research stays separate from your permanent style profile.",
  },
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
        <nav className="header-actions" aria-label="How it works navigation">
          <Link className="header-link" href="/">Home</Link>
          <a className="header-download" href={downloadUrl} download>
            Download <span aria-hidden="true">↓</span>
          </a>
        </nav>
      </header>

      <section className="how-hero" id="main-content">
        <div className="how-hero-copy">
          <p className="eyebrow"><span aria-hidden="true">✦</span> How it works</p>
          <h1>Set up in minutes.<br /><em>Stay in the sentence.</em></h1>
          <p>
            Shakespeare begins as a clean Mac editor. Connect one model account
            when you want help, decide what it may learn, and keep writing.
          </p>
          <div className="how-hero-facts" aria-label="Product setup facts">
            <span><strong>5 min</strong><small>Typical setup</small></span>
            <span><strong>1 key</strong><small>OpenRouter connection</small></span>
            <span><strong>Local</strong><small>Documents and style data</small></span>
          </div>
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
          <figcaption>Your draft stays the center of the experience.</figcaption>
        </figure>
      </section>

      <section className="how-section setup-section" aria-labelledby="setup-title">
        <div className="how-section-heading">
          <p className="eyebrow"><span aria-hidden="true">✦</span> Onboarding</p>
          <h2 id="setup-title">Three small steps.<br /><em>No account maze.</em></h2>
          <p>You can skip the model connection and start with the editor alone.</p>
        </div>

        <ol className="setup-grid">
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
                  Get an OpenRouter key <span aria-hidden="true">↗</span>
                </a>
              ) : (
                <span className="setup-note">{step.note}</span>
              )}
            </li>
          ))}
        </ol>
      </section>

      <section className="how-section features-section" aria-labelledby="features-title">
        <div className="how-section-heading compact">
          <p className="eyebrow"><span aria-hidden="true">✦</span> Inside the app</p>
          <h2 id="features-title">Useful when needed.<br /><em>Quiet when not.</em></h2>
        </div>

        <div className="how-feature-grid">
          {features.map((feature) => (
            <article className="how-feature" key={feature.title}>
              <span className="feature-mark" aria-hidden="true">{feature.mark}</span>
              <h3>{feature.title}</h3>
              <p>{feature.body}</p>
            </article>
          ))}
        </div>
      </section>

      <aside className="privacy-band" aria-label="Privacy summary">
        <div>
          <p className="eyebrow light"><span aria-hidden="true">◆</span> Private by design</p>
          <h2>Your words are not the product.</h2>
        </div>
        <p>
          Documents, versions, samples, and learned preferences live on your
          Mac. Only the excerpts needed for a model-powered action are sent,
          with provider data collection disabled.
        </p>
      </aside>

      <section className="how-cta">
        <img src="/app-icon.png" alt="Shakespeare app icon" />
        <div>
          <p className="eyebrow"><span aria-hidden="true">✦</span> Ready when you are</p>
          <h2>Open a draft. Keep your voice.</h2>
        </div>
        <a className="primary-button" href={downloadUrl} download>
          <span>Download for Mac</span>
          <span className="button-icon" aria-hidden="true">↓</span>
        </a>
      </section>

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
