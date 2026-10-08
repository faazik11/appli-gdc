// Fichiers gardés sur l'appareil (Cache Storage) et rendu des pages PDF en images (PDF.js).
import * as pdfjsLib from './pdfjs/pdf.min.mjs';

pdfjsLib.GlobalWorkerOptions.workerSrc = './pdfjs/pdf.worker.min.mjs';

const CACHE = 'gdc-fichiers-v1';
const docs = new Map();
let nextId = 0;

const url = (key) => './gdc-fichier/' + encodeURIComponent(key);

window.gdcFiles = {
  async get(key) {
    try {
      const cache = await caches.open(CACHE);
      const res = await cache.match(url(key));
      return res ? new Uint8Array(await res.arrayBuffer()) : null;
    } catch (e) {
      return null;
    }
  },

  async put(key, bytes) {
    try {
      const cache = await caches.open(CACHE);
      await cache.put(url(key), new Response(bytes.slice()));
      return true;
    } catch (e) {
      return false;
    }
  },

  async open(bytes) {
    const doc = await pdfjsLib.getDocument({ data: bytes.slice() }).promise;
    const id = ++nextId;
    docs.set(id, doc);
    return id;
  },

  pageCount(id) {
    return docs.get(id)?.numPages ?? 0;
  },

  // Rend la page [index] (à partir de 0) en JPEG, à la largeur demandée en pixels.
  async render(id, index, width) {
    const doc = docs.get(id);
    const page = await doc.getPage(index + 1);
    const base = page.getViewport({ scale: 1 });
    const viewport = page.getViewport({ scale: width / base.width });
    const canvas = document.createElement('canvas');
    canvas.width = Math.round(viewport.width);
    canvas.height = Math.round(viewport.height);
    const ctx = canvas.getContext('2d');
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    await page.render({ canvasContext: ctx, viewport }).promise;
    page.cleanup();
    const blob = await new Promise((resolve) => canvas.toBlob(resolve, 'image/jpeg', 0.88));
    canvas.width = canvas.height = 0;
    return new Uint8Array(await blob.arrayBuffer());
  },

  close(id) {
    docs.get(id)?.destroy();
    docs.delete(id);
  },
};
