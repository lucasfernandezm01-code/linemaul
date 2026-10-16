/* Line & Maul: app instalable. Siempre busca lo último en la red; si no hay conexión, muestra la última versión guardada. */
const CACHE = "lm-v2";
const SHELL = ["./", "index.html", "manifest.webmanifest", "icon-192.png", "logo-512.png", "apple-touch-icon.png"];
self.addEventListener("install", e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting())); });
self.addEventListener("activate", e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener("fetch", e => {
  const r = e.request; const u = new URL(r.url);
  if (r.method !== "GET" || u.origin !== location.origin) return; /* la base (Supabase) y otros sitios van directo */
  const fresh = (r.mode === "navigate" || u.pathname.endsWith(".html") || u.pathname.endsWith("/")) ? fetch(r, { cache: "no-cache" }) : fetch(r);
  e.respondWith(fresh.then(res => { if (res.ok) { const cp = res.clone(); caches.open(CACHE).then(c => c.put(r, cp)); } return res; })
    .catch(() => caches.match(r).then(m => m || (r.mode === "navigate" ? caches.match("index.html") : undefined))));
});
