import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);

test("ships a minimal app-aligned landing page and a fail-closed release action", async () => {
  const [html, css, editorImage, appIcon, favicon, headers] = await Promise.all([
    readFile(new URL("public/index.html", root), "utf8"),
    readFile(new URL("public/v4/styles.css", root), "utf8"),
    readFile(new URL("public/v4/shakespeare-editor.jpg", root)),
    readFile(new URL("public/v4/app-icon.png", root)),
    readFile(new URL("public/v4/favicon.png", root)),
    readFile(new URL("public/_headers", root), "utf8"),
  ]);

  assert.match(html, /^<!doctype html>/i);
  assert.match(html, /class="app-frame"/);
  assert.match(html, /v4\/shakespeare-editor\.jpg/);
  assert.match(html, /v4\/app-icon\.png/);
  assert.match(html, /v4\/favicon\.png/);
  assert.match(html, /<h1[^>]*>Write like yourself\.<\/h1>/);
  assert.match(html, /A writing app for Mac/);
  assert.match(html, /A quiet editor that helps without taking over\./);
  assert.match(html, /<li>Local-first<\/li>/);
  assert.match(html, /<li>Review every change<\/li>/);
  assert.match(html, /<li>Research with sources<\/li>/);
  assert.match(html, /Release unavailable/);
  assert.match(html, /data-release-action aria-disabled="true"/);
  assert.match(html, /<!-- release-control:start -->[\s\S]*<!-- release-control:end -->/);
  assert.match(html, /href="https:\/\/github\.com\/rmcentush\/shakespeare"/);
  assert.match(html, />Source<\/a>/);
  assert.doesNotMatch(html, /Shakespeare-latest\.zip/);
  assert.equal((html.match(/<img\b/g) ?? []).length, 1);
  assert.equal((html.match(/<section\b/g) ?? []).length, 1);
  assert.equal((html.match(/data-release-action/g) ?? []).length, 1);
  assert.match(html, /<header\b[\s\S]*<nav\b[\s\S]*<footer\b/i);
  assert.doesNotMatch(html, /<script\b/i);
  assert.doesNotMatch(css, /@import|url\(/i);
  assert.match(css, /--blue: #0062cc/i);
  assert.match(css, /Georgia/);
  assert.match(css, /-apple-system/);
  assert.match(css, /@media \(max-width: 900px\)/);
  assert.match(css, /@media \(max-width: 600px\)/);
  assert.match(css, /prefers-reduced-motion/);
  assert.ok(editorImage.length > 50_000);
  assert.ok(appIcon.length > 100_000);
  assert.ok(favicon.length < 50_000);
  assert.deepEqual([...editorImage.subarray(0, 3)], [0xff, 0xd8, 0xff]);
  assert.deepEqual([...appIcon.subarray(1, 4)], [0x50, 0x4e, 0x47]);
  assert.deepEqual([...favicon.subarray(1, 4)], [0x50, 0x4e, 0x47]);
  assert.match(headers, /Content-Security-Policy: default-src 'none'/);
  assert.match(headers, /X-Frame-Options: DENY/);
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
  const manifest = {
    version: "1.2.3",
    buildNumber: 123,
    archiveKey,
    sha256,
    bundleIdentifier: "com.shakespeare.app",
    teamIdentifier: "AB12CD34EF",
    notarized: true,
    sourceCommit: "b".repeat(40),
  };
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
          return { json: async () => manifest };
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
    ["head", archiveKey],
    ["get", "releases/current.json"],
    ["head", archiveKey],
  ]);
});

test("enables the landing-page download only for a verified release manifest", async () => {
  const { default: worker } = await import("../worker/index.js");
  const source = await readFile(new URL("public/index.html", root), "utf8");
  const env = {
    ASSETS: {
      fetch: async () => new Response(source, {
        headers: { "Content-Type": "text/html; charset=utf-8", ETag: '"static"' },
      }),
    },
    RELEASES: {
      get: async (key) => key === "releases/current.json" ? {
        json: async () => ({
          version: "1.2.3",
          buildNumber: 123,
          archiveKey: "releases/v1.2.3/Shakespeare.zip",
          sha256: "a".repeat(64),
          bundleIdentifier: "com.shakespeare.app",
          teamIdentifier: "AB12CD34EF",
          notarized: true,
          sourceCommit: "b".repeat(40),
        }),
      } : null,
      head: async (key) => key === "releases/v1.2.3/Shakespeare.zip"
        ? { size: 1 }
        : null,
    },
  };

  const response = await worker.fetch(new Request("https://writeshakespeare.com/"), env);
  const html = await response.text();
  assert.match(html, /<a class="download" data-release-action/);
  assert.match(html, /Shakespeare-latest\.zip/);
  assert.doesNotMatch(html, /Release unavailable/);
  assert.equal(response.headers.get("etag"), null);
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

test("degrades safely when R2 operations fail", async () => {
  const { default: worker } = await import("../worker/index.js");
  const source = await readFile(new URL("public/index.html", root), "utf8");
  const validManifest = {
    version: "1.2.3",
    buildNumber: 123,
    archiveKey: "releases/v1.2.3/Shakespeare.zip",
    sha256: "a".repeat(64),
    bundleIdentifier: "com.shakespeare.app",
    teamIdentifier: "AB12CD34EF",
    notarized: true,
    sourceCommit: "b".repeat(40),
  };

  const missingManifest = await worker.fetch(
    new Request("https://writeshakespeare.com/downloads/Shakespeare-latest.zip"),
    {
      ASSETS: { fetch: async () => new Response(source) },
      RELEASES: { get: async () => { throw new Error("R2 unavailable"); } },
    },
  );
  assert.equal(missingManifest.status, 503);
  assert.equal(missingManifest.headers.get("x-content-type-options"), "nosniff");

  const homepage = await worker.fetch(new Request("https://writeshakespeare.com/"), {
    ASSETS: {
      fetch: async () => new Response(source, {
        headers: { "Content-Type": "text/html; charset=utf-8" },
      }),
    },
    RELEASES: {
      get: async () => ({ json: async () => validManifest }),
      head: async () => { throw new Error("R2 unavailable"); },
    },
  });
  assert.equal(homepage.status, 200);
  assert.match(await homepage.text(), /Release unavailable/);

  const archive = await worker.fetch(
    new Request("https://writeshakespeare.com/downloads/Shakespeare-latest.zip"),
    {
      ASSETS: { fetch: async () => new Response(source) },
      RELEASES: {
        get: async (key) => {
          if (key === "releases/current.json") return { json: async () => validManifest };
          throw new Error("R2 unavailable");
        },
      },
    },
  );
  assert.equal(archive.status, 503);
});
