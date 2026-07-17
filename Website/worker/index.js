/** Cloudflare Worker entry point for the static Shakespeare website. */
export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.hostname === "www.writeshakespeare.com") {
      url.hostname = "writeshakespeare.com";
      return Response.redirect(url.toString(), 308);
    }

    if (url.pathname === "/how-it-works" || url.pathname === "/how-it-works/") {
      return Response.redirect(`${url.origin}/#how-it-works`, 308);
    }

    return env.ASSETS.fetch(request);
  },
};
