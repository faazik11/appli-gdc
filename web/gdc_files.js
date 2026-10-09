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

  // Proportions de la première page et sommaire (signets) : [titre, page, niveau].
  async info(id) {
    const doc = docs.get(id);
    const first = await doc.getPage(1);
    const vp = first.getViewport({ scale: 1 });
    const outline = [];
    const walk = async (items, depth) => {
      for (const item of items ?? []) {
        try {
          let dest = item.dest;
          if (typeof dest === 'string') dest = await doc.getDestination(dest);
          if (Array.isArray(dest)) {
            const page = await doc.getPageIndex(dest[0]);
            outline.push([item.title, page, depth]);
          }
        } catch (e) {}
        await walk(item.items, depth + 1);
      }
    };
    try {
      await walk(await doc.getOutline(), 0);
    } catch (e) {}
    return { ratio: vp.height / vp.width, outline };
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

  // Adresse locale (blob:) pour lire un fichier gardé, par exemple un MP3.
  objectUrl(bytes, type) {
    return URL.createObjectURL(new Blob([bytes], { type }));
  },

  close(id) {
    docs.get(id)?.destroy();
    docs.delete(id);
  },

  async remove(key) {
    try {
      const cache = await caches.open(CACHE);
      return await cache.delete(url(key));
    } catch (e) {
      return false;
    }
  },

  // Réduit une photo (le plus grand côté à maxSide pixels) et la renvoie en JPEG.
  async shrinkImage(bytes, maxSide) {
    try {
      const bitmap = await createImageBitmap(new Blob([bytes]));
      const scale = Math.min(1, maxSide / Math.max(bitmap.width, bitmap.height));
      const canvas = document.createElement('canvas');
      canvas.width = Math.round(bitmap.width * scale);
      canvas.height = Math.round(bitmap.height * scale);
      canvas.getContext('2d').drawImage(bitmap, 0, 0, canvas.width, canvas.height);
      bitmap.close();
      const blob = await new Promise((resolve) => canvas.toBlob(resolve, 'image/jpeg', 0.85));
      canvas.width = canvas.height = 0;
      return new Uint8Array(await blob.arrayBuffer());
    } catch (e) {
      return bytes;
    }
  },
};

// Enregistrement audio avec le micro (MediaRecorder). Voix : mono, débit réduit
// (≈ 11 Mo par heure) pour que 2 h de répétition restent sous la limite de 50 Mo.
let rec = null;
window.gdcRecorder = {
  supported() {
    return !!(navigator.mediaDevices && window.MediaRecorder);
  },

  async start() {
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: true, channelCount: 1 },
    });
    const types = ['audio/mp4;codecs=mp4a.40.2', 'audio/mp4', 'audio/webm;codecs=opus', 'audio/webm'];
    const mimeType = types.find((t) => MediaRecorder.isTypeSupported(t)) ?? '';
    const recorder = new MediaRecorder(stream, { mimeType, audioBitsPerSecond: 24000 });
    const chunks = [];
    recorder.ondataavailable = (e) => e.data.size && chunks.push(e.data);
    // Niveau du micro pour le témoin à l'écran
    let analyser = null;
    try {
      const ctx = new AudioContext();
      analyser = ctx.createAnalyser();
      analyser.fftSize = 512;
      ctx.createMediaStreamSource(stream).connect(analyser);
      rec = { ctx };
    } catch (e) {}
    recorder.start(5000);
    rec = { ...(rec ?? {}), recorder, stream, chunks, analyser, paused: false };
    return recorder.mimeType || mimeType || 'audio/webm';
  },

  level() {
    const a = rec?.analyser;
    if (!a) return 0;
    const data = new Uint8Array(a.fftSize);
    a.getByteTimeDomainData(data);
    let peak = 0;
    for (const v of data) peak = Math.max(peak, Math.abs(v - 128));
    return peak / 128;
  },

  pause() {
    if (rec?.recorder.state === 'recording') rec.recorder.pause();
  },

  resume() {
    if (rec?.recorder.state === 'paused') rec.recorder.resume();
  },

  async stop() {
    if (!rec) return null;
    const { recorder, stream, chunks, ctx } = rec;
    rec = null;
    await new Promise((resolve) => {
      recorder.onstop = resolve;
      recorder.stop();
    });
    stream.getTracks().forEach((t) => t.stop());
    try {
      ctx?.close();
    } catch (e) {}
    const blob = new Blob(chunks, { type: recorder.mimeType });
    return new Uint8Array(await blob.arrayBuffer());
  },
};
