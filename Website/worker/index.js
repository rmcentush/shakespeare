const releaseManifestKey = "releases/current.json";
const archivePath = "/downloads/Shakespeare-latest.zip";
const checksumPath = `${archivePath}.sha256`;
const releaseControlPattern =
  /<!-- release-control:start -->[\s\S]*?<!-- release-control:end -->/;

function unavailableResponse() {
  return new Response("Release unavailable", {
    status: 503,
    headers: {
      "Cache-Control": "no-store",
      "Content-Type": "text/plain; charset=utf-8",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

function validManifest(value) {
  return Boolean(
    value &&
      typeof value === "object" &&
      typeof value.version === "string" &&
      /^\d+\.\d+(?:\.\d+)?$/.test(value.version) &&
      /^releases\/v?[0-9]+(?:\.[0-9]+){1,2}\/Shakespeare\.zip$/.test(
      value.archiveKey,
      ) &&
      value.archiveKey === `releases/v${value.version}/Shakespeare.zip` &&
      typeof value.sha256 === "string" &&
      /^[0-9a-f]{64}$/.test(value.sha256) &&
      Number.isSafeInteger(value.buildNumber) &&
      value.buildNumber > 0 &&
      value.bundleIdentifier === "com.shakespeare.app" &&
      typeof value.teamIdentifier === "string" &&
      /^[A-Z0-9]{10}$/.test(value.teamIdentifier) &&
      value.notarized === true &&
      typeof value.sourceCommit === "string" &&
      /^[0-9a-f]{40,64}$/.test(value.sourceCommit),
  );
}

async function serveHome(request, env) {
  const response = await env.ASSETS.fetch(request);
  if (
    request.method !== "GET" ||
    !response.ok ||
    !response.headers.get("content-type")?.includes("text/html")
  ) {
    return response;
  }

  const manifest = await loadReleaseManifest(env);
  if (!manifest) return response;
  let archive;
  try {
    archive = await env.RELEASES.head(manifest.archiveKey);
  } catch (error) {
    console.error("Release archive metadata lookup failed", error);
    return response;
  }
  if (!archive || archive.size <= 0) return response;

  const available = `<!-- release-control:start -->
          <a class="download" data-release-action href="${archivePath}" download>
            <span>Download for Mac</span>
            <span aria-hidden="true">↓</span>
          </a>
          <!-- release-control:end -->`;
  const source = await response.text();
  if (!releaseControlPattern.test(source)) {
    console.error("Landing page release marker is missing");
    return new Response(source, {
      status: response.status,
      statusText: response.statusText,
      headers: response.headers,
    });
  }
  const html = source.replace(releaseControlPattern, available);
  const headers = new Headers(response.headers);
  headers.delete("content-encoding");
  headers.delete("content-length");
  headers.delete("etag");
  headers.set("Cache-Control", "public, max-age=60");
  headers.set("X-Content-Type-Options", "nosniff");
  return new Response(html, { status: response.status, headers });
}

async function loadReleaseManifest(env) {
  try {
    const object = await env.RELEASES.get(releaseManifestKey);
    if (!object) return null;
    const value = await object.json();
    return validManifest(value) ? value : null;
  } catch (error) {
    console.error("Release manifest lookup failed", error);
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
    return unavailableResponse();
  }

  if (pathname === checksumPath) {
    try {
      const archive = await env.RELEASES.head(manifest.archiveKey);
      if (!archive || archive.size <= 0) return unavailableResponse();
    } catch (error) {
      console.error("Release checksum archive lookup failed", error);
      return unavailableResponse();
    }
    const body = `${manifest.sha256}  Shakespeare-latest.zip\n`;
    const headers = new Headers({
      "Cache-Control": "no-cache",
      "Content-Type": "text/plain; charset=utf-8",
      "X-Content-Type-Options": "nosniff",
      "X-Shakespeare-SHA256": manifest.sha256,
      "X-Shakespeare-Bundle-ID": manifest.bundleIdentifier,
      "X-Shakespeare-Team-ID": manifest.teamIdentifier,
    });
    return new Response(request.method === "HEAD" ? null : body, { headers });
  }

  let object;
  try {
    object = request.method === "HEAD"
      ? await env.RELEASES.head(manifest.archiveKey)
      : await env.RELEASES.get(manifest.archiveKey);
  } catch (error) {
    console.error("Release archive lookup failed", error);
    return unavailableResponse();
  }
  if (!object) {
    return unavailableResponse();
  }
  if (!Number.isSafeInteger(object.size) || object.size <= 0) {
    return unavailableResponse();
  }

  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("Cache-Control", "public, max-age=300");
  headers.set("Content-Disposition", 'attachment; filename="Shakespeare-latest.zip"');
  headers.set("Content-Length", String(object.size));
  headers.set("ETag", object.httpEtag);
  headers.set("X-Content-Type-Options", "nosniff");
  headers.set("X-Shakespeare-SHA256", manifest.sha256);
  headers.set("X-Shakespeare-Bundle-ID", manifest.bundleIdentifier);
  headers.set("X-Shakespeare-Team-ID", manifest.teamIdentifier);

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

    if (url.pathname === "/") {
      return serveHome(request, env);
    }

    return env.ASSETS.fetch(request);
  },
};
