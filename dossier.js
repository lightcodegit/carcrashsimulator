"use strict";
// Site behavior: reveal-on-scroll, sticky header state, ticker tape, and the
// frame-cost instrument. The bench model is the p_perf data (Intel HD 630,
// 1600x900, live rendering): 61% of a preset's cost is resolution-independent,
// 39% scales as (s/0.7)^2 — anchors 6.7 ms geometry at 70% and 9.4 ms at 100%.
const REDUCED = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
const dict = () => (window.CCS_I18N && window.CCS_I18N[window.CCS_LANG || "en"]) || { en: "" };

/* ---------- reveal on scroll ---------- */

const obs = new IntersectionObserver(entries => {
  for (const e of entries) {
    if (e.isIntersecting) { e.target.classList.add("visible"); obs.unobserve(e.target); }
  }
}, { threshold: 0.12 });

document.querySelectorAll(".reveal").forEach(node => obs.observe(node));

/* ---------- sticky header + reading progress ---------- */

const topbar = document.getElementById("topbar");
const progress = document.getElementById("progress");
function onScroll() {
  topbar.classList.toggle("scrolled", window.scrollY > 24);
  const max = document.documentElement.scrollHeight - window.innerHeight;
  const p = max > 0 ? window.scrollY / max : 0;
  if (progress) progress.style.width = (p * 100).toFixed(2) + "%";
}
window.addEventListener("scroll", onScroll, { passive: true });
window.addEventListener("resize", onScroll, { passive: true });
onScroll();

/* ---------- stat numbers count up when they enter the viewport ---------- */

const statObs = new IntersectionObserver(entries => {
  for (const e of entries) {
    if (e.isIntersecting) { statObs.unobserve(e.target); countUp(e.target); }
  }
}, { threshold: 0.5 });

document.querySelectorAll(".stat b").forEach(node => statObs.observe(node));

function countUp(node) {
  // Animate every digit-only text node; the "5/7" stat keeps its styled slash.
  const parts = [...node.childNodes].filter(n =>
    n.nodeType === 3 && n.textContent.trim() !== "").map(n => ({
      n,
      to: parseInt(n.textContent, 10),
      ok: /^\s*\d+\s*$/.test(n.textContent),
    }));
  if (!parts.length || !parts.every(p => p.ok) || REDUCED) return;
  const DUR = 1200;
  const t0 = performance.now();
  requestAnimationFrame(function step(t) {
    const k = Math.min(1, (t - t0) / DUR);
    const e = 1 - Math.pow(1 - k, 3);
    for (const p of parts) p.n.textContent = String(Math.round(p.to * e));
    if (k < 1) requestAnimationFrame(step);
  });
}

/* ---------- ticker tape: duplicate the tokens once for a seamless loop ---------- */

const tape = document.getElementById("tape");
if (tape) tape.append(...Array.from(tape.children).map(n => n.cloneNode(true)));

/* ---------- the frame-cost instrument ---------- */

const PRESETS = [
  { key: "p0", ms0: 6.7 },   // LOW   — geometry only, no shadows or post
  { key: "p1", ms0: 13.7 },  // MEDIUM — haze and glow, shadows 120 m (default)
  { key: "p2", ms0: 29.4 },  // HIGH  — everything on: SSAO/SSIL, MSAA 4x
  { key: "p3", ms0: 29.2 },  // FILM  — soft shadows 420 m, bloom
];
const BUDGET = 16.7;        // 60 Hz
const OVERLOAD = 33.4;      // the top of the scale

const el = id => document.getElementById(id);
const msEl = el("b-ms"), fpsEl = el("b-fps"), nameEl = el("b-name"),
      verdictEl = el("b-verdict"), rangeEl = el("b-ms-range"),
      fillEl = el("b-fill"),
      scaleEl = el("b-scale-readout"), meterEl = fillEl && fillEl.parentElement,
      qBtns = document.querySelectorAll("#b-presets button");

const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
const msAt = (p, s) => PRESETS[p].ms0 * (0.61 + 0.39 * Math.pow(s / 0.7, 2));

let preset = 1;   // MEDIUM by default, like the game
let scale = 0.7;  // the slider's render scale, 0.5..1.0
let ms = msAt(preset, scale); // derived frame cost

let shownMs = ms, shownFps = 1000 / ms;
function tick() {
  const targetFps = 1000 / ms;
  if (!REDUCED) {
    shownMs += (ms - shownMs) * 0.22;
    shownFps += (targetFps - shownFps) * 0.22;
  } else {
    shownMs = ms;
    shownFps = targetFps;
  }
  msEl.textContent = shownMs.toFixed(1);
  fpsEl.textContent = String(Math.round(shownFps));

  const zone = ms > OVERLOAD ? "zone-over" : ms > BUDGET ? "zone-drop" : "zone-ok";
  meterEl.classList.remove("zone-ok", "zone-drop", "zone-over");
  meterEl.classList.add(zone);

  // the fill is a readout: the cost drawn on the 0..OVERLOAD instrument scale
  fillEl.style.width = clamp(ms / OVERLOAD * 100, 0, 100).toFixed(1) + "%";

  const d = dict();
  if (ms <= BUDGET) {
    verdictEl.textContent = d.v_fit(Math.round(targetFps));
    verdictEl.classList.remove("warn");
  } else if (ms <= OVERLOAD) {
    verdictEl.textContent = d.v_drop(Math.round(targetFps));
    verdictEl.classList.add("warn");
  } else {
    verdictEl.textContent = d.v_gpu;
    verdictEl.classList.add("warn");
  }
  if (scaleEl) scaleEl.textContent = d.scale_lbl(Math.round(scale * 100));
  requestAnimationFrame(tick);
}
requestAnimationFrame(tick);

function syncName() {
  const d = dict();
  nameEl.textContent = d[PRESETS[preset].key];
  qBtns.forEach((b, j) => {
    b.classList.toggle("on", j === preset);
    b.textContent = d[PRESETS[j].key];
  });
}

function syncRange() {
  rangeEl.value = String(Math.round(scale * 100));
}

// Preset = composition; scale is carried over as the user left it.
function setPreset(p) {
  preset = p;
  ms = msAt(p, scale);
  syncName();
}

rangeEl.addEventListener("input", () => {
  scale = clamp(+rangeEl.value, 50, 100) / 100;
  ms = msAt(preset, scale);
});

qBtns.forEach((b, j) => b.addEventListener("click", () => setPreset(j)));

// Called by i18n.js after a language switch.
window.ccsRefreshBench = syncName;
syncRange();
syncName();
