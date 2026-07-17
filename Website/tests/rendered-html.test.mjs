import assert from "node:assert/strict";
import test from "node:test";

async function render(url = "http://localhost/") {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request(url, { headers: { accept: "text/html" } }),
    { ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) } },
    { waitUntil() {}, passThroughOnException() {} },
  );
}

test("renders the Shakespeare download page", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<title>Shakespeare — Write like yourself\.<\/title>/i);
  assert.match(html, /Write like yourself/);
  assert.match(html, /Download for Mac/);
  assert.match(html, /How it works/);
  assert.match(html, /Shakespeare-latest\.zip/);
  assert.match(html, /shakespeare-editor\.jpg/);
  assert.match(html, /Actual app/);
  assert.match(html, /macOS 14\+/);
  assert.match(html, /https:\/\/writeshakespeare\.com\//);
  assert.doesNotMatch(html, /github\.com|>Source<|>GitHub</i);
  assert.doesNotMatch(html, /codex-preview|react-loading-skeleton/i);
});

test("renders the Shakespeare setup and feature guide", async () => {
  const response = await render("https://writeshakespeare.com/how-it-works");
  assert.equal(response.status, 200);

  const html = await response.text();
  assert.match(html, /<title>How Shakespeare works<\/title>/i);
  assert.match(html, /Three steps/);
  assert.match(html, /Paste one OpenRouter key/);
  assert.match(html, /Choose what it learns/);
  assert.match(html, /Four tools/);
  assert.match(html, /Research/);
  assert.match(html, /Private by design/);
  assert.match(html, /aria-current="page"[^>]*>How it works</i);
  assert.doesNotMatch(html, /github\.com|>Source<|>GitHub</i);
});

test("redirects www to the canonical domain", async () => {
  const response = await render("https://www.writeshakespeare.com/download");
  assert.equal(response.status, 308);
  assert.equal(
    response.headers.get("location"),
    "https://writeshakespeare.com/download",
  );
});
