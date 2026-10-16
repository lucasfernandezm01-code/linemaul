// Line & Maul · robot de notificaciones push (lo corre GitHub cada 15 minutos).
import webpush from "web-push";

const SB = "https://srdnktmbipvpvyzguuyk.supabase.co";
const KEY = "sb_publishable_Z9QwgewyOFo0ujjxhCE91Q_OR8a_7yh";
const VAPID_PUBLIC = "BAY0kOg2olgVmmQ7FJ0Rtxsm-U_TtaXTIPsLmZ7WaZf0kEK7DsA7uojC0GzvlnSkYZgNn3XNCx3tzfn3dslGGRs";
const { VAPID_PRIVATE, PUSH_TOKEN } = process.env;
const SITE = "https://lucasfernandezm01-code.github.io/linemaul/";
if (!VAPID_PRIVATE || !PUSH_TOKEN) { console.log("Faltan las claves (VAPID_PRIVATE / PUSH_TOKEN). No se manda nada."); process.exit(0); }
webpush.setVapidDetails("mailto:lucasfernandezm01@gmail.com", VAPID_PUBLIC, VAPID_PRIVATE);

const H = { apikey: KEY, Authorization: "Bearer " + KEY, "Content-Type": "application/json" };
async function rest(path) { const r = await fetch(SB + "/rest/v1/" + path, { headers: H }); if (!r.ok) throw new Error(path + " " + r.status + " " + await r.text()); return r.json(); }
async function rpc(fn, args) { const r = await fetch(SB + "/rest/v1/rpc/" + fn, { method: "POST", headers: H, body: JSON.stringify(Object.assign({ tok: PUSH_TOKEN }, args)) }); if (!r.ok) throw new Error(fn + " " + r.status + " " + await r.text()); const t = await r.text(); return t ? JSON.parse(t) : null; }

const now = Date.now();
const ART = 3 * 3600e3; // Argentina: UTC-3
const local = t => new Date(t - ART); // usar getUTC* sobre esto = hora argentina
function isOpen(f) {
  const d = f.data || {}; const st = d.estado || "auto";
  if (st === "cerrada" || st === "final") return false;
  if (st === "abierta" && d.manual) return true;
  const a = f.abre ? Date.parse(f.abre) : null, c = f.cierra ? Date.parse(f.cierra) : null;
  return (!a || now >= a) && (!c || now < c);
}

async function send(targets, msg, want) {
  let ok = 0;
  for (const t of targets) {
    if (!want(t)) continue;
    const m = typeof msg === "function" ? msg(t) : msg; if (!m) continue;
    try { await webpush.sendNotification(t.sub, JSON.stringify(m), { TTL: 12 * 3600 }); ok++; }
    catch (e) { if (e.statusCode === 404 || e.statusCode === 410) await rpc("push_drop", { ep: t.endpoint }); else console.log("error", e.statusCode, e.body); }
  }
  return ok;
}
const pref = k => t => !t.prefs || t.prefs[k] !== false;

const fechas = await rest("fechas?select=id,data,abre,cierra");
for (const f of fechas) {
  const d = f.data || {}; const name = d.nombre || "la fecha";
  const abre = f.abre ? Date.parse(f.abre) : null, cierra = f.cierra ? Date.parse(f.cierra) : null;
  const open = isOpen(f); const L = local(now);
  const jobs = [];
  if (open && abre && now >= abre && now - abre < 12 * 3600e3)
    jobs.push(["abre", { title: "¡Abrió la fecha! 🏉", body: "Armá tu XV y hacé el Prode.", url: SITE }, pref("abre")]);
  if (open && L.getUTCDay() === 5 && L.getUTCHours() >= 21)
    jobs.push(["form", { title: "Formaciones confirmadas", body: "Ya están todas las formaciones. Confirmá tu XV de la fecha.", url: SITE + "?go=dt" }, pref("form")]);
  if (open && cierra && cierra - now <= 2 * 3600e3 && cierra > now)
    jobs.push(["cierre", t => { const x = !t.has_xv, p = !t.has_prode; if (!x && !p) return null;
      return { title: "La fecha cierra en 2 h ⏰", body: x && p ? "Todavía no armaste tu XV ni hiciste el Prode." : x ? "Todavía no armaste tu XV." : "Todavía no hiciste el Prode.", url: SITE + (x ? "?go=dt" : "?go=prode") }; }, pref("cierre")]);
  if (d.estado === "final" && cierra && now - cierra < 7 * 864e5) {
    jobs.push(["puntos", { title: "¡Puntos publicados!", body: "Entrá y mirá cómo te fue en la fecha.", url: SITE + "?go=dt" }, pref("puntos")]);
  }
  if (!jobs.length) continue;
  const targets = await rpc("push_targets", { fid: f.id });
  for (const [k, msg, want] of jobs) {
    if (!(await rpc("push_mark", { k: k + ":" + f.id }))) continue;
    console.log(k, f.id, "→", await send(targets, msg, want));
  }
}

const manual = (await rpc("push_take", {})) || [];
if (manual.length) {
  const targets = await rpc("push_targets", { fid: "" });
  for (const q of manual) {
    const n = await send(targets, { title: q.title, body: q.body, url: q.url ? SITE + q.url : SITE }, pref("avisos"));
    await rpc("push_done", { qid: q.id, n }); console.log("manual", q.id, "→", n);
  }
}
console.log("listo");
