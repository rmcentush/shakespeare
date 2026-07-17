import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);

test("ships only the desk, sea, writing tools, and download action", async () => {
  const html = await readFile(new URL("public/index.html", root), "utf8");
  const css = await readFile(new URL("public/styles.css", root), "utf8");

  assert.match(html, /^<!doctype html>/i);
  assert.match(html, /class="window"/);
  assert.match(html, /class="sea"/);
  assert.match(html, /class="desk"/);
  assert.match(html, /class="paper"/);
  assert.match(html, /class="pen"/);
  assert.match(html, /Download Shakespeare/);
  assert.match(html, /Shakespeare-latest\.zip/);
  assert.equal((html.match(/<a\b/g) ?? []).length, 1);
  assert.doesNotMatch(html, /<header\b|<nav\b|<footer\b|<section\b|<img\b|<script\b/i);
  assert.doesNotMatch(html, /Write like yourself|How it works|shakespeare-editor|app-icon|og-v5/i);
  assert.doesNotMatch(css, /@import|url\(/i);
  assert.match(css, /prefers-reduced-motion/);
});

test("redirects retired routes before serving the scene", async () => {
  const { default: worker } = await import("../worker/index.js");
  const env = {
    ASSETS: {
      fetch: async () => new Response("static asset", { status: 200 }),
    },
    RELEASES: {
      get: async () => null,
      head: async () => null,
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

test("serves one release atomically from an R2 manifest", async () => {
  const { default: worker } = await import("../worker/index.js");
  const sha256 = "a".repeat(64);
  const archiveKey = "releases/v1.2.3/Shakespeare.zip";
  const archive = new TextEncoder().encode("signed archive");
  const calls = [];
  const releaseObject = {
    body: archive,
    httpEtag: '"release-etag"',
    size: archive.byteLength,
    writeHttpMetadata(headers) {
      headers.set("Content-Type", "application/zip");
    },
  };
  const env = {
    ASSETS: {
      fetch: async () => new Response("static asset", { status: 200 }),
    },
    RELEASES: {
      async get(key) {
        calls.push(["get", key]);
        if (key === "releases/current.json") {
          return { json: async () => ({ version: "1.2.3", archiveKey, sha256 }) };
        }
        return key === archiveKey ? releaseObject : null;
      },
      async head(key) {
        calls.push(["head", key]);
        return key === archiveKey ? releaseObject : null;
      },
    },
  };

  const archiveResponse = await worker.fetch(
    new Request("https://writeshakespeare.com/downloads/Shakespeare-latest.zip"),
    env,
  );
  assert.equal(archiveResponse.status, 200);
  assert.equal(await archiveResponse.text(), "signed archive");
  assert.equal(archiveResponse.headers.get("content-type"), "application/zip");
  assert.equal(archiveResponse.headers.get("x-shakespeare-sha256"), sha256);

  const checksumResponse = await worker.fetch(
    new Request(
      "https://writeshakespeare.com/downloads/Shakespeare-latest.zip.sha256",
    ),
    env,
  );
  assert.equal(await checksumResponse.text(), `${sha256}  Shakespeare-latest.zip\n`);

  const headResponse = await worker.fetch(
    new Request("https://writeshakespeare.com/downloads/Shakespeare-latest.zip", {
      method: "HEAD",
    }),
    env,
  );
  assert.equal(headResponse.status, 200);
  assert.equal(await headResponse.text(), "");
  assert.deepEqual(calls, [
    ["get", "releases/current.json"],
    ["get", archiveKey],
    ["get", "releases/current.json"],
    ["get", "releases/current.json"],
    ["head", archiveKey],
  ]);
});

test("fails closed when the R2 release manifest is invalid", async () => {
  const { default: worker } = await import("../worker/index.js");
  const env = {
    ASSETS: { fetch: async () => new Response("static asset") },
    RELEASES: {
      get: async () => ({ json: async () => ({ archiveKey: "unsafe", sha256: "no" }) }),
      head: async () => null,
    },
  };

  const response = await worker.fetch(
    new Request("https://writeshakespeare.com/downloads/Shakespeare-latest.zip"),
    env,
  );
  assert.equal(response.status, 503);
  assert.equal(response.headers.get("cache-control"), "no-store");
});
