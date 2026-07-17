const releaseManifestKey = "releases/current.json";
const archivePath = "/downloads/Shakespeare-latest.zip";
const checksumPath = `${archivePath}.sha256`;

function validManifest(value) {
  return Boolean(
    value &&
      typeof value === "object" &&
      typeof value.version === "string" &&
      /^releases\/v?[0-9]+(?:\.[0-9]+){1,2}\/Shakespeare\.zip$/.test(
        value.archiveKey,
      ) &&
      typeof value.sha256 === "string" &&
      /^[0-9a-f]{64}$/.test(value.sha256),
  );
}

async function loadReleaseManifest(env) {
  const object = await env.RELEASES.get(releaseManifestKey);
  if (!object) return null;

  try {
    const value = await object.json();
    return validManifest(value) ? value : null;
  } catch {
    return null;
  }
}

async function serveRelease(request, env, pathname) {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response("Method Not Allowed", {
      status: 405,
      headers: { Allow: "GET, HEAD" },
    });
  }

  const manifest = await loadReleaseManifest(env);
  if (!manifest) {
    return new Response("Release unavailable", {
      status: 503,
      headers: { "Cache-Control": "no-store" },
    });
  }

  if (pathname === checksumPath) {
    const body = `${manifest.sha256}  Shakespeare-latest.zip\n`;
    const headers = new Headers({
      "Cache-Control": "no-cache",
      "Content-Type": "text/plain; charset=utf-8",
      "X-Content-Type-Options": "nosniff",
      "X-Shakespeare-SHA256": manifest.sha256,
    });
    return new Response(request.method === "HEAD" ? null : body, { headers });
  }

  const object =
    request.method === "HEAD"
      ? await env.RELEASES.head(manifest.archiveKey)
      : await env.RELEASES.get(manifest.archiveKey);
  if (!object) {
    return new Response("Release unavailable", {
      status: 503,
      headers: { "Cache-Control": "no-store" },
    });
  }

  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("Cache-Control", "public, max-age=300");
  headers.set("Content-Disposition", 'attachment; filename="Shakespeare-latest.zip"');
  headers.set("Content-Length", String(object.size));
  headers.set("ETag", object.httpEtag);
  headers.set("X-Content-Type-Options", "nosniff");
  headers.set("X-Shakespeare-SHA256", manifest.sha256);

  return new Response(request.method === "HEAD" ? null : object.body, { headers });
}

/** Cloudflare Worker entry point for the static scene and its R2 release. */
export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.hostname === "www.writeshakespeare.com") {
      url.hostname = "writeshakespeare.com";
      return Response.redirect(url.toString(), 308);
    }

    if (url.pathname === "/how-it-works" || url.pathname === "/how-it-works/") {
      return Response.redirect(`${url.origin}/`, 308);
    }

    if (url.pathname === archivePath || url.pathname === checksumPath) {
      return serveRelease(request, env, url.pathname);
    }

    return env.ASSETS.fetch(request);
  },
};
