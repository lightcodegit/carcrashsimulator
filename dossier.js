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

/* ---------- sticky header ---------- */

const topbar = document.getElementById("topbar");
function onScroll() {
  topbar.classList.toggle("scrolled", window.scrollY > 24);
}
window.addEventListener("scroll", onScroll, { passive: true });
onScroll();

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
const scaleFor = (p, v) =>
  clamp(0.7 * Math.sqrt(Math.max(0, (v / PRESETS[p].ms0 - 0.61) / 0.39)), 0.5, 1);
const msBounds = p => [msAt(p, 0.5), Math.min(msAt(p, 1.0), OVERLOAD)];

let preset = 1;   // MEDIUM by default, like the game
let ms = 13.7;    // slider value, milliseconds
let scale = 0.7;  // derived render scale

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

  const over = ms > OVERLOAD;
  meterEl.classList.toggle("over", over && !REDUCED);
  msEl.parentElement.classList.toggle("over", over || ms > BUDGET);

  // fill and thumb share the same 0..OVERLOAD scale
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

function syncRange() {
  const [lo, hi] = msBounds(preset);
  rangeEl.min = lo.toFixed(1);
  rangeEl.max = hi.toFixed(1);
  rangeEl.step = "0.1";
  rangeEl.value = ms.toFixed(1);
}

function syncName() {
  const d = dict();
  nameEl.textContent = d[PRESETS[preset].key];
  qBtns.forEach((b, j) => {
    b.classList.toggle("on", j === preset);
    b.textContent = d[PRESETS[j].key];
  });
}

function setPreset(p) {
  preset = p;
  const [lo, hi] = msBounds(p);
  ms = clamp(msAt(p, scale), lo, hi); // keep the render scale when switching
  syncRange();
  syncName();
}

rangeEl.addEventListener("input", () => {
  const [lo, hi] = msBounds(preset);
  ms = clamp(+rangeEl.value, lo, hi);
  scale = scaleFor(preset, ms);
  syncRange();
});
qBtns.forEach((b, j) => b.addEventListener("click", () => setPreset(j)));

// Called by i18n.js after a language switch.
window.ccsRefreshBench = syncName;
syncRange();
syncName();
