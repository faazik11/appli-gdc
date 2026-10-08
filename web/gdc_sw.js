// Service worker de l'appli GDC : garde l'appli sur l'appareil pour l'ouvrir sans internet.
// - Code de l'appli (html, js, json) : réseau d'abord (toujours la dernière version), copie gardée sinon.
// - Le reste (moteur graphique, polices, images) : copie gardée d'abord, mise à jour en arrière-plan.
const APP_CACHE = 'gdc-appli-v1';
const KEEP = [APP_CACHE, 'gdc-fichiers-v1'];

const CORE = [
  './',
  'index.html',
  'flutter_bootstrap.js',
  'main.dart.js',
  'manifest.json',
  'gdc_files.js',
  'favicon.png',
  'icons/Icon-192.png',
  'icons/apple-touch-icon.png',
  'pdfjs/pdf.min.mjs',
  'pdfjs/pdf.worker.min.mjs',
  'canvaskit/canvaskit.js',
  'canvaskit/canvaskit.wasm',
  'canvaskit/chromium/canvaskit.js',
  'canvaskit/chromium/canvaskit.wasm',
  'assets/FontManifest.json',
  'assets/AssetManifest.bin',
  'assets/AssetManifest.bin.json',
];

async function precache() {
  const cache = await caches.open(APP_CACHE);
  const urls = [...CORE];
  try {
    // Polices et ressources déclarées par l'appli
    const fonts = await (await fetch('assets/FontManifest.json', { cache: 'no-store' })).json();
    for (const family of fonts) for (const f of family.fonts) urls.push('assets/' + f.asset);
  } catch (e) {}
  await Promise.all(
    urls.map(async (url) => {
      try {
        const res = await fetch(url, { cache: 'no-store' });
        if (res.ok) await cache.put(url, res);
      } catch (e) {}
    }),
  );
}

self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(precache());
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      for (const key of await caches.keys()) if (!KEEP.includes(key)) await caches.delete(key);
      await self.clients.claim();
    })(),
  );
});

const isCode = (url) => /\.(js|mjs|json|html)$/.test(url.pathname) || url.pathname.endsWith('/');

async function networkFirst(request) {
  const cache = await caches.open(APP_CACHE);
  try {
    const res = await Promise.race([
      fetch(request, { cache: 'no-store' }),
      new Promise((_, reject) => setTimeout(() => reject(new Error('lent')), 5000)),
    ]);
    if (res.ok) cache.put(request, res.clone());
    return res;
  } catch (e) {
    const saved =
      (await cache.match(request, { ignoreSearch: true })) ||
      (request.mode === 'navigate' ? await cache.match('./') : undefined);
    if (saved) return saved;
    throw e;
  }
}

async function cacheFirst(request) {
  const cache = await caches.open(APP_CACHE);
  const saved = await cache.match(request, { ignoreSearch: true });
  const refresh = fetch(request)
    .then((res) => {
      if (res.ok) cache.put(request, res.clone());
      return res;
    })
    .catch(() => undefined);
  return saved || (await refresh) || Response.error();
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  // Seulement les fichiers de l'appli (pas Supabase, YouTube…)
  if (url.origin !== self.location.origin) return;
  if (url.pathname.includes('/gdc-fichier/')) return;
  event.respondWith(isCode(url) || request.mode === 'navigate' ? networkFirst(request) : cacheFirst(request));
});
