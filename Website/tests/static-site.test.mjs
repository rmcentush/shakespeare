import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);

test("ships one minimal static HTML page", async () => {
  const html = await readFile(new URL("public/index.html", root), "utf8");
  const css = await readFile(new URL("public/styles.css", root), "utf8");

  assert.match(html, /^<!doctype html>/i);
  assert.match(html, /Write like yourself\./);
  assert.match(html, /shakespeare-editor\.jpg/);
  assert.match(html, /id="how-it-works"/);
  assert.match(html, /Shakespeare-latest\.zip/);
  assert.match(html, /og-v5\.png/);
  assert.doesNotMatch(html, /<script\b|github\.com|>Source<|>GitHub</i);
  assert.doesNotMatch(css, /@import|url\(/i);
});

test("redirects legacy and www URLs before serving assets", async () => {
  const { default: worker } = await import("../worker/index.js");
  const env = {
    ASSETS: {
      fetch: async () => new Response("static asset", { status: 200 }),
    },
  };

  const www = await worker.fetch(new Request("https://www.writeshakespeare.com/test"), env);
  assert.equal(www.status, 308);
  assert.equal(www.headers.get("location"), "https://writeshakespeare.com/test");

  const legacy = await worker.fetch(new Request("https://writeshakespeare.com/how-it-works"), env);
  assert.equal(legacy.status, 308);
  assert.equal(legacy.headers.get("location"), "https://writeshakespeare.com/#how-it-works");

  const asset = await worker.fetch(new Request("https://writeshakespeare.com/"), env);
  assert.equal(await asset.text(), "static asset");
});
