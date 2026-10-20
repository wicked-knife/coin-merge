// The engine exceeds Pages' 25 MiB asset limit before compression. Stream the
// .gz files as already encoded responses; setting _headers alone re-encodes them.
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const types = {
      "/index.wasm": "application/wasm",
      "/index.pck": "application/octet-stream",
    };
    const contentType = types[url.pathname];
    if (!contentType) return env.ASSETS.fetch(request);
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method not allowed", { status: 405, headers: { Allow: "GET, HEAD" } });
    }

    url.pathname += ".gz";
    const asset = await env.ASSETS.fetch(new Request(url, request));
    if (asset.status !== 200 && asset.status !== 304) return asset;
    const headers = new Headers(asset.headers);
    headers.set("Content-Type", contentType);
    headers.set("Content-Encoding", "gzip");
    headers.set("Cache-Control", "public, max-age=0, must-revalidate, no-transform");
    headers.set("X-Content-Type-Options", "nosniff");
    return new Response(asset.body, {
      status: asset.status,
      statusText: asset.statusText,
      headers,
      encodeBody: "manual",
    });
  },
};
