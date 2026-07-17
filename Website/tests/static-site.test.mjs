import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);

test("ships one generated scene and one download action", async () => {
  const [html, css, hero] = await Promise.all([
    readFile(new URL("public/index.html", root), "utf8"),
    readFile(new URL("public/styles.css", root), "utf8"),
    readFile(new URL("public/sea-desk-hero.jpg", root)),
  ]);

  assert.match(html, /^<!doctype html>/i);
  assert.match(html, /class="scene-image"/);
  assert.match(html, /sea-desk-hero\.jpg/);
  assert.match(html, /Download Shakespeare/);
  assert.match(html, /Shakespeare-latest\.zip/);
  assert.equal((html.match(/<a\b/g) ?? []).length, 1);
  assert.equal((html.match(/<img\b/g) ?? []).length, 1);
  assert.doesNotMatch(html, /<header\b|<nav\b|<footer\b|<section\b|<script\b/i);
  assert.doesNotMatch(html, /Write like yourself|How it works|shakespeare-editor|app-icon|og-v5/i);
  assert.doesNotMatch(css, /@import|url\(/i);
  assert.match(css, /prefers-reduced-motion/);
  assert.ok(hero.length > 100_000);
  assert.deepEqual([...hero.subarray(0, 3)], [0xff, 0xd8, 0xff]);
});

test("redirects retired routes before serving the scene", async () => {
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
  assert.equal(legacy.headers.get("location"), "https://writeshakespeare.com/");

  const asset = await worker.fetch(new Request("https://writeshakespeare.com/"), env);
  assert.equal(await asset.text(), "static asset");
});
