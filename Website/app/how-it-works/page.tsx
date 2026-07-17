import type { Metadata } from "next";
import Link from "next/link";

/* eslint-disable @next/next/no-img-element -- local product captures are intentionally served directly */

const downloadUrl = "/downloads/Shakespeare-latest.zip";

export const metadata: Metadata = {
  title: "How Shakespeare works",
  description: "See how Shakespeare keeps writing private, useful, and unmistakably yours.",
  alternates: { canonical: "/how-it-works" },
  openGraph: {
    title: "How Shakespeare works",
    description: "Write normally. Ask when stuck. Decide what stays.",
    url: "/how-it-works",
  },
};

const chapters = [
  {
    number: "01",
    eyebrow: "Write normally",
    title: "The editor stays out of your way.",
    body: "Draft, format, and keep versions in a quiet native Mac app. Your documents remain local, and nothing is sent simply because you are typing.",
  },
  {
    number: "02",
    eyebrow: "Ask when stuck",
    title: "Bring help to the sentence.",
    body: "Select a passage for revision, turn on paragraph-scoped grammar checks, or research a question beside the draft with linked sources.",
  },
  {
    number: "03",
    eyebrow: "Decide what stays",
    title: "Your judgment closes the loop.",
    body: "Keep, change, or reject every suggestion. Style learning is optional, reviewable, and shaped by the rewrites you actually save.",
  },
];

const principles = [
  ["Local", "Documents, versions, and style data stay on your Mac."],
  ["Reviewable", "You can inspect every durable writing preference."],
  ["Reversible", "Pause learning, edit the profile, or clear it entirely."],
];

export default function HowItWorks() {
  return (
    <main className="walkthrough-page">
      <a className="skip-link" href="#main-content">Skip to content</a>

      <header className="site-header walkthrough-header">
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

      <section className="walkthrough-hero" id="main-content">
        <div className="walkthrough-title">
          <p className="eyebrow light"><span aria-hidden="true">✦</span> How it works</p>
          <h1>From blank page<br />to <em>better draft.</em></h1>
        </div>
        <div className="walkthrough-intro">
          <p>
            Shakespeare does not write over you. It keeps the page quiet,
            brings help close when you ask, and leaves every decision in your hands.
          </p>
          <a href="#story">Follow the writing loop <span aria-hidden="true">↓</span></a>
        </div>
        <div className="walkthrough-beats" aria-label="The Shakespeare writing loop">
          <span><i>01</i><strong>Write</strong><small>Local by default</small></span>
          <span><i>02</i><strong>Ask</strong><small>Help in context</small></span>
          <span><i>03</i><strong>Decide</strong><small>You keep control</small></span>
        </div>
      </section>

      <section className="story-section" id="story">
        <div className="story-visual">
          <p className="visual-caption"><span><i aria-hidden="true" /> Actual app</span><span>The writing room</span></p>
          <div className="editor-capture">
            <img
              src="/shakespeare-editor.jpg"
              width="1131"
              height="701"
              alt="The real Shakespeare editor showing a formatted essay"
            />
          </div>
          <div className="setup-peek">
            <span>Two-choice setup</span>
            <img
              src="/shakespeare-setup.jpg"
              width="350"
              height="190"
              alt="Shakespeare setup showing the OpenRouter connection and optional style learning"
            />
          </div>
        </div>

        <div className="story-copy">
          {chapters.map((chapter) => (
            <article className="story-chapter" key={chapter.number}>
              <span className="chapter-number">{chapter.number}</span>
              <p className="chapter-eyebrow">{chapter.eyebrow}</p>
              <h2>{chapter.title}</h2>
              <p>{chapter.body}</p>
            </article>
          ))}
        </div>
      </section>

      <section className="setup-story" aria-labelledby="setup-title">
        <div className="setup-story-copy">
          <p className="eyebrow"><span aria-hidden="true">✦</span> Five-minute setup</p>
          <h2 id="setup-title">One connection.<br /><em>One choice.</em></h2>
          <p>
            Paste one OpenRouter key if you want model-powered writing and research.
            Then choose whether Shakespeare may learn from saved rewrites. Both can be
            skipped, changed, or removed later.
          </p>
          <div className="setup-actions">
            <a href="https://openrouter.ai/settings/keys">Get an OpenRouter key <span aria-hidden="true">↗</span></a>
            <span>Stored in macOS Keychain</span>
          </div>
        </div>
        <figure className="setup-capture">
          <img
            src="/shakespeare-setup.jpg"
            width="350"
            height="190"
            alt="The real Shakespeare onboarding screen"
          />
          <figcaption>Connect once. Personalize only if you want to.</figcaption>
        </figure>
      </section>

      <section className="principles" aria-label="Shakespeare privacy principles">
        {principles.map(([title, body], index) => (
          <article key={title}>
            <span>0{index + 1}</span>
            <h2>{title}</h2>
            <p>{body}</p>
          </article>
        ))}
      </section>

      <section className="walkthrough-cta">
        <div>
          <p className="eyebrow light"><span aria-hidden="true">✦</span> Ready when you are</p>
          <h2>Keep the voice.<br /><em>Lose the friction.</em></h2>
        </div>
        <div>
          <p>Latest beta for macOS 14+.<br />Apple silicon and Intel.</p>
          <a className="walkthrough-download" href={downloadUrl} download>
            <span>Download Shakespeare</span><span aria-hidden="true">↓</span>
          </a>
        </div>
      </section>

      <footer className="walkthrough-footer">
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
