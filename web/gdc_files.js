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

// Enregistrement audio avec le micro (MediaRecorder). Voix : même son des deux côtés, débit réduit
// (≈ 15 Mo par heure) pour que 2 h de répétition restent sous la limite de 50 Mo.
//
// Le son est écrit sur le téléphone toutes les 5 s (IndexedDB) : si l'iPhone coupe l'appli
// (écran verrouillé, appel, appli quittée), ce qui a été enregistré est récupéré au retour.
// Quand l'appli revient au premier plan, le micro est rebranché sur le même enregistrement.
const REC_DB = 'gdc-enregistrements';

function recDb() {
  return new Promise((resolve, reject) => {
    const r = indexedDB.open(REC_DB, 1);
    r.onupgradeneeded = () => {
      const db = r.result;
      db.createObjectStore('sessions', { keyPath: 'id' });
      db.createObjectStore('morceaux', { autoIncrement: true }).createIndex('session', 'session');
    };
    r.onsuccess = () => resolve(r.result);
    r.onerror = () => reject(r.error);
  });
}
const idbReq = (r) =>
  new Promise((resolve, reject) => {
    r.onsuccess = () => resolve(r.result);
    r.onerror = () => reject(r.error);
  });

let rec = null;
window.gdcRecorder = {
  supported() {
    return !!(navigator.mediaDevices && window.MediaRecorder);
  },

  async start() {
    // Contexte audio créé tout de suite, pendant l'appui sur le bouton (exigé par l'iPhone).
    let ctx = null;
    try {
      ctx = new (window.AudioContext || window.webkitAudioContext)();
      ctx.resume();
    } catch (e) {}
    const mic = await this._mic();
    // Le micro est ramené en mono puis copié sur les deux côtés : sinon l'iPhone
    // peut produire un fichier qu'on n'entend que dans l'écouteur gauche.
    let stream = mic;
    let analyser = null;
    let mono = null;
    let source = null;
    if (ctx) {
      try {
        if (ctx.state !== 'running') await ctx.resume();
        source = ctx.createMediaStreamSource(mic);
        mono = new GainNode(ctx, { channelCount: 1, channelCountMode: 'explicit', channelInterpretation: 'speakers' });
        const both = new GainNode(ctx, { channelCount: 2, channelCountMode: 'explicit', channelInterpretation: 'speakers' });
        const out = ctx.createMediaStreamDestination();
        out.channelCount = 2;
        source.connect(mono).connect(both).connect(out);
        analyser = ctx.createAnalyser();
        analyser.fftSize = 512;
        mono.connect(analyser);
        if (ctx.state === 'running') stream = out.stream;
        else mono = null;
      } catch (e) {
        stream = mic;
        mono = null;
      }
    }
    const types = ['audio/mp4;codecs=mp4a.40.2', 'audio/mp4', 'audio/webm;codecs=opus', 'audio/webm'];
    const mimeType = types.find((t) => MediaRecorder.isTypeSupported(t)) ?? '';
    const id = 'rec-' + Date.now();
    rec = {
      id, ctx, mic, source, mono, analyser, stream, mimeType,
      segments: [], recorder: null, db: null, writes: Promise.resolve(),
      cuts: 0, lostMs: 0, hiddenAt: null, broken: false, paused: false,
    };
    try {
      rec.db = await recDb();
      await idbReq(
        rec.db.transaction('sessions', 'readwrite').objectStore('sessions')
          .put({ id, mime: mimeType, startedAt: Date.now(), lastAt: Date.now() }),
      );
    } catch (e) {
      rec.db = null;
    }
    this._newSegment();
    this._watch();
    return rec.recorder.mimeType || mimeType || 'audio/webm';
  },

  _mic() {
    return navigator.mediaDevices.getUserMedia({
      audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: true },
    });
  },

  // Un « segment » = un fichier audio. Il n'y en a qu'un, sauf si l'iPhone a arrêté l'enregistreur.
  _newSegment() {
    const r = rec;
    const recorder = new MediaRecorder(r.stream, { mimeType: r.mimeType, audioBitsPerSecond: 32000 });
    const seg = { index: r.segments.length, chunks: [], startedAt: Date.now(), endedAt: null, pausedMs: 0 };
    r.segments.push(seg);
    recorder.ondataavailable = (e) => {
      if (!e.data.size) return;
      seg.chunks.push(e.data);
      if (!r.db) return;
      // Écrit dans l'ordre, morceau après morceau.
      r.writes = r.writes.then(async () => {
        try {
          const data = await e.data.arrayBuffer();
          const tx = r.db.transaction(['morceaux', 'sessions'], 'readwrite');
          tx.objectStore('morceaux').add({ session: r.id, segment: seg.index, data });
          tx.objectStore('sessions').put({ id: r.id, mime: r.mimeType, startedAt: r.segments[0].startedAt, lastAt: Date.now() });
          await new Promise((ok) => (tx.oncomplete = tx.onerror = ok));
        } catch (err) {}
      });
    };
    recorder.onstop = () => (seg.endedAt = seg.endedAt || Date.now());
    recorder.start(5000);
    r.recorder = recorder;
  },

  _watch() {
    const r = rec;
    const mark = () => {
      if (rec !== r || r.broken) return;
      r.broken = true;
      r.cuts++;
      r.brokenAt = r.hiddenAt || Date.now();
    };
    r.onVisibility = () => {
      if (rec !== r) return;
      if (document.visibilityState === 'hidden') r.hiddenAt = Date.now();
      else {
        // Retour dans l'appli : on vérifie que tout tourne encore, sinon on répare.
        if (r.hiddenAt && Date.now() - r.hiddenAt > 2000 && !this._healthy()) mark();
        r.hiddenAt = null;
        this.heal();
      }
    };
    document.addEventListener('visibilitychange', r.onVisibility);
    this._watchMic(mark);
    r.ctx?.addEventListener('statechange', () => {
      if (rec === r && r.ctx.state !== 'running' && r.ctx.state !== 'closed') mark();
    });
    r.check = setInterval(() => {
      if (rec !== r) return clearInterval(r.check);
      if (!this._healthy()) {
        mark();
        if (document.visibilityState === 'visible') this.heal();
      }
    }, 2000);
  },

  _watchMic(mark) {
    const track = rec.mic.getAudioTracks()[0];
    track?.addEventListener('ended', mark);
    track?.addEventListener('mute', mark);
  },

  _healthy() {
    const r = rec;
    if (!r) return true;
    const track = r.mic.getAudioTracks()[0];
    const micOk = track && track.readyState === 'live' && !track.muted;
    const ctxOk = !r.ctx || !r.mono || r.ctx.state === 'running';
    const recOk = r.recorder.state !== 'inactive';
    return micOk && ctxOk && recOk;
  },

  // Rebranche ce qui a été coupé. Peut demander un toucher sur iPhone : renvoie true si tout tourne.
  async heal() {
    const r = rec;
    if (!r) return true;
    if (r.healing) return r.healing;
    r.healing = (async () => {
      try {
        if (r.ctx && r.mono && r.ctx.state !== 'running') await r.ctx.resume();
        const track = r.mic.getAudioTracks()[0];
        if (!track || track.readyState !== 'live' || track.muted) {
          const mic = await this._mic();
          if (r.mono) {
            const source = r.ctx.createMediaStreamSource(mic);
            source.connect(r.mono);
            try {
              r.source?.disconnect();
            } catch (e) {}
            r.source = source;
            r.mic.getTracks().forEach((t) => t.stop());
            r.mic = mic;
          } else {
            // Sans le mélangeur audio, il faut un nouvel enregistreur sur le nouveau micro.
            r.mic.getTracks().forEach((t) => t.stop());
            r.mic = mic;
            r.stream = mic;
            if (r.recorder.state !== 'inactive') r.recorder.stop();
          }
          this._watchMic(() => {
            if (rec === r && !r.broken) {
              r.broken = true;
              r.cuts++;
              r.brokenAt = Date.now();
            }
          });
        }
        if (r.recorder.state === 'inactive') this._newSegment();
        if (r.paused && r.recorder.state === 'recording') r.recorder.pause();
        const ok = this._healthy();
        if (ok && r.broken) {
          r.broken = false;
          r.lostMs += Date.now() - (r.brokenAt || Date.now());
        }
        return ok;
      } catch (e) {
        return false;
      } finally {
        r.healing = null;
      }
    })();
    return r.healing;
  },

  // État pour l'écran : { ok, cuts, lostSeconds }
  status() {
    const r = rec;
    if (!r) return JSON.stringify({ ok: true, cuts: 0, lostSeconds: 0 });
    const ok = !r.broken && this._healthy();
    const lost = r.lostMs + (r.broken ? Date.now() - (r.brokenAt || Date.now()) : 0);
    return JSON.stringify({ ok, cuts: r.cuts, lostSeconds: Math.round(lost / 1000) });
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
    if (!rec) return;
    rec.paused = true;
    rec.pausedAt = Date.now();
    if (rec.recorder.state === 'recording') rec.recorder.pause();
  },

  resume() {
    if (!rec) return;
    rec.paused = false;
    const seg = rec.segments[rec.segments.length - 1];
    if (rec.pausedAt) seg.pausedMs += Date.now() - rec.pausedAt;
    rec.pausedAt = null;
    if (rec.recorder.state === 'paused') rec.recorder.resume();
  },

  sessionId() {
    return rec ? rec.id : null;
  },

  // Pour les tests : l'enregistrement en cours.
  _current() {
    return rec;
  },

  // Arrête et renvoie les fichiers : [{ bytes, startedAt, seconds }] (un seul en temps normal).
  async stop() {
    if (!rec) return [];
    const r = rec;
    rec = null;
    clearInterval(r.check);
    document.removeEventListener('visibilitychange', r.onVisibility);
    if (r.recorder.state !== 'inactive') {
      await new Promise((resolve) => {
        r.recorder.addEventListener('stop', resolve, { once: true });
        r.recorder.stop();
      });
    }
    await r.writes;
    r.mic.getTracks().forEach((t) => t.stop());
    try {
      r.ctx?.close();
    } catch (e) {}
    const out = [];
    for (const seg of r.segments) {
      if (!seg.chunks.length) continue;
      const blob = new Blob(seg.chunks, { type: r.recorder.mimeType || r.mimeType });
      const end = seg.endedAt || Date.now();
      out.push({
        bytes: new Uint8Array(await blob.arrayBuffer()),
        startedAt: seg.startedAt,
        seconds: Math.max(1, Math.round((end - seg.startedAt - seg.pausedMs) / 1000)),
      });
    }
    return out;
  },

  // Enregistrements interrompus (appli fermée pendant l'enregistrement) restés sur le téléphone.
  async drafts() {
    try {
      const db = await recDb();
      const sessions = await idbReq(db.transaction('sessions').objectStore('sessions').getAll());
      return JSON.stringify(sessions.filter((s) => !rec || s.id !== rec.id));
    } catch (e) {
      return '[]';
    }
  },

  // Fichiers d'un enregistrement interrompu : [{ bytes, startedAt, seconds }].
  async draftFiles(id) {
    const db = await recDb();
    const tx = db.transaction(['morceaux', 'sessions']);
    const session = await idbReq(tx.objectStore('sessions').get(id));
    const rows = await idbReq(tx.objectStore('morceaux').index('session').getAll(id));
    const bySegment = new Map();
    for (const row of rows) {
      if (!bySegment.has(row.segment)) bySegment.set(row.segment, []);
      bySegment.get(row.segment).push(row.data);
    }
    const out = [];
    for (const [, parts] of [...bySegment.entries()].sort((a, b) => a[0] - b[0])) {
      const blob = new Blob(parts, { type: session?.mime || 'audio/mp4' });
      out.push({
        bytes: new Uint8Array(await blob.arrayBuffer()),
        startedAt: session?.startedAt || Date.now(),
        seconds: parts.length * 5,
      });
    }
    return out;
  },

  async clearDraft(id) {
    try {
      const db = await recDb();
      const tx = db.transaction(['morceaux', 'sessions'], 'readwrite');
      const keys = await idbReq(tx.objectStore('morceaux').index('session').getAllKeys(id));
      for (const k of keys) tx.objectStore('morceaux').delete(k);
      tx.objectStore('sessions').delete(id);
      await new Promise((ok) => (tx.oncomplete = tx.onerror = ok));
    } catch (e) {}
  },
};

// ---------- Notifications sur le téléphone (Web Push) ----------
window.gdcPush = {
  supported() {
    return 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
  },
  permission() {
    return this.supported() ? Notification.permission : 'unsupported';
  },
  async _registration() {
    return (await navigator.serviceWorker.getRegistration()) || (await navigator.serviceWorker.register('gdc_sw.js'));
  },
  // À appeler directement depuis un toucher : iPhone n'accepte la demande qu'à ce moment-là.
  // Renvoie l'abonnement en JSON, ou null si refusé.
  async subscribe(publicKey) {
    const asked = Notification.requestPermission();
    if ((await asked) !== 'granted') return null;
    const reg = await this._registration();
    await navigator.serviceWorker.ready;
    let sub = await reg.pushManager.getSubscription();
    if (!sub) {
      const raw = atob(publicKey.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (publicKey.length % 4)) % 4));
      const key = Uint8Array.from(raw, (c) => c.charCodeAt(0));
      sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: key });
    }
    return this._json(sub);
  },
  // Abonnement existant (si les notifications sont déjà autorisées), sinon null.
  async current() {
    if (!this.supported() || Notification.permission !== 'granted') return null;
    const reg = await navigator.serviceWorker.getRegistration();
    const sub = reg && (await reg.pushManager.getSubscription());
    return sub ? this._json(sub) : null;
  },
  // Coupe les notifications sur cet appareil ; renvoie l'adresse de l'abonnement supprimé.
  async unsubscribe() {
    if (!this.supported()) return null;
    const reg = await navigator.serviceWorker.getRegistration();
    const sub = reg && (await reg.pushManager.getSubscription());
    if (!sub) return null;
    const endpoint = sub.endpoint;
    await sub.unsubscribe();
    return endpoint;
  },
  _json(sub) {
    const j = sub.toJSON();
    return JSON.stringify({ endpoint: j.endpoint, p256dh: j.keys.p256dh, auth: j.keys.auth });
  },
};
