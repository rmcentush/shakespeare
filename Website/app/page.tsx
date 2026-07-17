/* eslint-disable @next/next/no-img-element -- the local app icon is intentionally served directly */

const downloadUrl = "/downloads/Shakespeare-latest.zip";

const features = [
  {
    number: "01",
    label: "Local by design",
    title: "Private by default",
    body: "Your documents, versions, and writing profile live on your Mac. You decide when a passage is sent for help.",
    detail: "Documents · History · Style profile",
  },
  {
    number: "02",
    label: "Personal, not generic",
    title: "Sounds like you",
    body: "Reviewable preferences help Shakespeare sharpen a draft without flattening the rhythm and choices that make it yours.",
    detail: "Consent-led · Editable · Reversible",
  },
  {
    number: "03",
    label: "Stay in the sentence",
    title: "Research in the margin",
    body: "Ask questions beside the draft and receive current, source-linked answers without leaving the writing room.",
    detail: "Current answers · Linked sources · Read-only",
  },
];

const workflow = ["Draft", "Revise", "Proof", "Research"];

export default function Home() {
  return (
    <main id="top">
      <a className="skip-link" href="#main-content">
        Skip to content
      </a>

      <header className="site-header">
        <div className="announcement" aria-label="Release information">
          <span><i aria-hidden="true" /> Shakespeare beta</span>
          <span>Native for macOS 14+</span>
        </div>
        <nav className="nav" aria-label="Primary navigation">
          <a className="brand" href="#top" aria-label="Shakespeare home">
            <img src="/app-icon.png" alt="" />
            <span>Shakespeare</span>
          </a>
          <div className="nav-links">
            <a href="#philosophy">Philosophy</a>
            <a href="#features">Inside the app</a>
            <a href="https://github.com/rmcentush/shakespeare">Source</a>
            <a className="nav-download" href={downloadUrl} download>
              Download <span aria-hidden="true">↓</span>
            </a>
          </div>
        </nav>
      </header>

      <section className="hero" id="main-content">
        <div className="hero-copy">
          <p className="eyebrow"><span aria-hidden="true">✦</span> A writing room for your Mac</p>
          <h1>
            Write like yourself.
            <em>Only sharper.</em>
          </h1>
          <p className="hero-lede">
            A calm, local-first writing app with thoughtful revision, private
            style learning, and source-backed research built in.
          </p>
          <div className="hero-actions">
            <a className="button button-primary" href={downloadUrl} download>
              <span>Download for Mac</span>
              <span className="button-icon" aria-hidden="true">↓</span>
            </a>
            <a className="text-link" href="#features">
              Explore the writing room <span aria-hidden="true">↘</span>
            </a>
          </div>
          <div className="compatibility" aria-label="Compatibility">
            <span>Universal Mac app</span>
            <span>Apple silicon + Intel</span>
            <span>13.4 MB</span>
          </div>
        </div>

        <div className="hero-visual" aria-label="Preview of the Shakespeare editor">
          <div className="hero-monogram" aria-hidden="true">S</div>
          <div className="halo" aria-hidden="true" />
          <div className="editor-window">
            <div className="window-bar">
              <div className="traffic-lights" aria-hidden="true"><i /><i /><i /></div>
              <span>The shape of an afternoon</span>
              <span className="saved-state"><i aria-hidden="true" /> Saved</span>
            </div>
            <div className="toolbar-preview" aria-hidden="true">
              <span>Body</span><b>B</b><em>I</em><span>¶</span>
              <i />
              <span className="toolbar-right">1,284 words</span>
            </div>
            <div className="editor-body">
              <aside className="document-rail" aria-hidden="true">
                <p>Drafts</p>
                <span className="document-row active"><i />Afternoon</span>
                <span className="document-row"><i />On quiet</span>
                <span className="document-row"><i />Field notes</span>
                <p>Research</p>
                <span className="document-row"><i />City rhythm</span>
              </aside>
              <article className="paper-preview">
                <p className="paper-kicker">ESSAY · JULY 16</p>
                <h2>The shape of<br />an afternoon</h2>
                <p className="opening-copy">
                  There is a particular kind of quiet that arrives just after
                  lunch, when the city seems to loosen its collar.
                </p>
                <p className="selected-copy">
                  The hours ahead do not feel empty. They feel unwritten.
                </p>
                <p>
                  I used to fill that space on instinct. Now I try to notice
                  what the day is asking for.
                </p>
              </article>
              <aside className="assistant-preview">
                <div className="assistant-head">
                  <span><i aria-hidden="true">✦</i> Shakespeare</span>
                  <b aria-label="Close suggestion">×</b>
                </div>
                <div className="assistant-content">
                  <p className="assistant-label">RHYTHM</p>
                  <h3>Keep “unwritten.”</h3>
                  <p>The short sentence gives the word room to land. It sounds measured, not manufactured.</p>
                  <div className="assistant-actions" aria-hidden="true">
                    <span>Keep</span><span>Try another</span>
                  </div>
                </div>
                <div className="assistant-context"><i aria-hidden="true" /> Using your reviewed style</div>
              </aside>
            </div>
          </div>
          <div className="privacy-pill">
            <span className="privacy-mark" aria-hidden="true">◆</span>
            <span><strong>Local-first</strong><small>Your work stays yours</small></span>
          </div>
          <div className="flow-pill" aria-hidden="true"><span>12</span> versions saved</div>
        </div>
      </section>

      <div className="workflow" aria-label="Writing tools">
        <span className="workflow-label">One quiet workspace</span>
        {workflow.map((item, index) => (
          <span className="workflow-item" key={item}>
            <i>{String(index + 1).padStart(2, "0")}</i>{item}
          </span>
        ))}
      </div>

      <section className="philosophy" id="philosophy">
        <div className="philosophy-aside">
          <p className="eyebrow light"><span aria-hidden="true">✦</span> The idea</p>
          <p>Shakespeare is not here to write over you.</p>
        </div>
        <div className="philosophy-main">
          <span className="quote-mark" aria-hidden="true">“</span>
          <h2>Technology should protect the quiet where good sentences begin.</h2>
          <p>
            So the editor stays calm, the learning stays reviewable, and your
            meaning always outranks the model.
          </p>
        </div>
      </section>

      <section className="features" id="features">
        <div className="section-heading">
          <p className="eyebrow"><span aria-hidden="true">✦</span> Built for the work</p>
          <h2>Everything useful.<br /><em>Nothing noisy.</em></h2>
          <p>Serious writing tools, designed to recede until the moment you need them.</p>
        </div>
        <div className="feature-list">
          {features.map((feature) => (
            <article className="feature" key={feature.number}>
              <div className="feature-topline">
                <span className="feature-number">{feature.number}</span>
                <span className="feature-label">{feature.label}</span>
              </div>
              <h3>{feature.title}</h3>
              <p>{feature.body}</p>
              <div className="feature-detail">
                <span>{feature.detail}</span>
                <i aria-hidden="true">↗</i>
              </div>
            </article>
          ))}
        </div>
      </section>

      <section className="facts" aria-label="Product facts">
        <div className="fact-intro">
          <p className="eyebrow light"><span aria-hidden="true">✦</span> Small by intention</p>
          <h2>A focused tool,<br />not a platform.</h2>
        </div>
        <div className="fact"><strong>1</strong><span>OpenRouter key<br /><small>One model connection</small></span></div>
        <div className="fact"><strong>0</strong><span>Usage markup<br /><small>Pay providers directly</small></span></div>
        <div className="fact"><strong>∞</strong><span>Your words<br /><small>Files remain on your Mac</small></span></div>
      </section>

      <section className="download-section" id="download">
        <div className="download-glow" aria-hidden="true" />
        <div className="download-inner">
          <img src="/app-icon.png" alt="Shakespeare app icon" />
          <p className="eyebrow light"><span aria-hidden="true">✦</span> Ready when you are</p>
          <h2>Give your writing<br /><em>a room of its own.</em></h2>
          <a className="button button-light" href={downloadUrl} download>
            <span>Download Shakespeare</span>
            <span className="button-icon" aria-hidden="true">↓</span>
          </a>
          <p className="install-copy">
            Latest beta · macOS 14 or later · Apple silicon and Intel
          </p>
          <p className="first-launch">
            Unzip, drag to Applications, then right-click and choose Open on the first launch.
          </p>
          <a className="checksum-link" href={`${downloadUrl}.sha256`} download>SHA-256 checksum</a>
        </div>
      </section>

      <footer>
        <a className="brand footer-brand" href="#top">
          <img src="/app-icon.png" alt="" />
          <span>Shakespeare</span>
        </a>
        <p>Made for writers who still want to sound human.</p>
        <div>
          <a href="https://github.com/rmcentush/shakespeare">GitHub</a>
          <a href="#features">Features</a>
          <a href="#download">Download</a>
        </div>
      </footer>
    </main>
  );
}
