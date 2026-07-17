/* eslint-disable @next/next/no-img-element -- local product assets are intentionally served directly */

const downloadUrl = "/downloads/Shakespeare-latest.zip";

const benefits = [
  {
    number: "01",
    title: "Private by design",
    body: "Documents and writing history stay on your Mac.",
  },
  {
    number: "02",
    title: "Learns with permission",
    body: "Review and edit every preference Shakespeare remembers.",
  },
  {
    number: "03",
    title: "Research in the margin",
    body: "Get current, linked answers without leaving your draft.",
  },
];

export default function Home() {
  return (
    <main className="landing">
      <a className="skip-link" href="#main-content">
        Skip to content
      </a>

      <header className="site-header">
        <a className="brand" href="#main-content" aria-label="Shakespeare home">
          <img src="/app-icon.png" alt="" />
          <span>Shakespeare.</span>
        </a>

        <div className="header-actions">
          <span className="release-note"><i aria-hidden="true" /> Beta for macOS 14+</span>
          <a className="header-download" href={downloadUrl} download>
            Download <span aria-hidden="true">↓</span>
          </a>
        </div>
      </header>

      <section className="hero" id="main-content">
        <div className="hero-copy">
          <p className="eyebrow"><span aria-hidden="true">✦</span> A private writing room for your Mac</p>
          <h1>Write like yourself.</h1>
          <p className="hero-lede">
            Shakespeare is a calm, local-first editor that helps you revise,
            research, and sharpen a draft without sanding away your voice.
          </p>

          <div className="hero-actions">
            <a className="primary-button" href={downloadUrl} download>
              <span>Download for Mac</span>
              <span className="button-icon" aria-hidden="true">↓</span>
            </a>
            <span className="download-meta">
              Latest beta<br />Apple silicon + Intel
            </span>
          </div>

          <div className="benefit-grid" aria-label="Shakespeare features">
            {benefits.map((benefit) => (
              <article className="benefit" key={benefit.number}>
                <span>{benefit.number}</span>
                <h2>{benefit.title}</h2>
                <p>{benefit.body}</p>
              </article>
            ))}
          </div>

          <div className="small-print">
            <span>One OpenRouter key</span>
            <span>Your files stay local</span>
            <a href={`${downloadUrl}.sha256`} download>SHA-256</a>
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
              alt="The real Shakespeare editor showing an essay titled The Shape of an Afternoon"
              fetchPriority="high"
            />
          </figure>
          <div className="privacy-card">
            <span className="privacy-icon" aria-hidden="true">◆</span>
            <span><strong>Local-first</strong><small>Your work stays yours.</small></span>
          </div>
          <p className="first-launch">First launch: unzip, drag to Applications, then right-click and choose Open.</p>
        </div>
      </section>
    </main>
  );
}
