"use strict";
// Бенчмарк: непрерывный ползунок масштаба поверх бара, две шкалы, count-up цифр,
// overload-тряска при провале ниже 30 fps. Модель: 61% цены кадра не зависит от
// масштаба рендера, 39% растёт как (s/0.7)² — анкеры: геометрия 6.7 мс на 70%
// и 9.4 мс на 100% (замеры p_perf на Intel UHD 730).
const PRESETS = [
  { name: "LOW",    ms: 6.7 },
  { name: "MEDIUM", ms: 13.7 },
  { name: "HIGH",   ms: 29.4 },
  { name: "FILM",   ms: 29.2 }
];
const BUDGET = 16.7;
const OVERLOAD_MS = 33.4;              // двойной бюджет 60 Гц: ниже — 30 fps
const REDUCED = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

const el = id => document.getElementById(id);
const msEl = el("b-ms"), nameEl = el("b-name"), fillEl = el("b-fill"),
      fpsEl = el("b-fps"), fpsFillEl = el("b-fpsfill"), verdictEl = el("b-verdict"),
      barEl = el("b-bar"), scaleEl = el("b-scale"),
      presetBtns = document.querySelectorAll("#b-presets button");

let quality = 1, scale = 70;

const frameMs = () => {
  const q = quality;   // непрерывная интерполяция между измеренными пресетами
  let ms = 0;
  const seg = [[0, 6.7], [1, 13.7], [2, 29.4], [3, 29.2]];
  for (let i = 0; i < seg.length - 1; i++) {
    const [a, va] = seg[i], [b, vb] = seg[i + 1];
    if (q >= a && q <= b) { ms = va + (vb - va) * ((q - a) / (b - a)); break; }
  }
  if (q > 3) ms = 29.2;
  return ms * 0.61 + ms * 0.39 * Math.pow(scale / 70, 2);
};

const fps = ms => 1000 / ms;
const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
const fmt1 = v => (Math.round(v * 10) / 10).toFixed(1);

// count-up: цифры катятся к цели, а не прыгают
function countUp(node, target, decimals) {
  const from = parseFloat(node.textContent) || 0;
  const t0 = performance.now(), dur = REDUCED ? 0 : 420;
  const tick = now => {
    const t = dur === 0 ? 1 : clamp((now - t0) / dur, 0, 1);
    const e = 1 - Math.pow(1 - t, 3);
    node.textContent = (from + (target - from) * e).toFixed(decimals);
    if (t < 1) requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
}

let overload = 0;
function render() {
  const ms = frameMs();
  const f = fps(ms);
  countUp(msEl, ms, 1);
  countUp(fpsEl, f, 0);
  // шкалы баров: бюджет 60 Гц лежит на ПОЛОВИНЕ каждой полосы (маркер .budget)
  fpsFillEl.style.width = clamp(f / 120 * 100, 2, 100) + "%";
  fillEl.style.width = clamp(ms / OVERLOAD_MS * 100, 2, 100) + "%";
  fillEl.style.background = ms <= BUDGET ? "var(--amber)" : "var(--hot)";
  barEl.classList.toggle("over", ms > BUDGET);
  barEl.classList.toggle("overload", ms > OVERLOAD_MS);
  overload = clamp((ms - BUDGET) / (OVERLOAD_MS - BUDGET), 0, 1);
  barEl.style.setProperty("--amp", (0.4 + overload * 2.2).toFixed(2));
  barEl.style.setProperty("--shake", (0.24 - overload * 0.1).toFixed(2) + "s");
  verdictEl.textContent = ms <= BUDGET ? "fits 60 Hz"
    : ms <= OVERLOAD_MS ? "drops to 30 Hz" : "needs a discrete GPU";
  verdictEl.classList.toggle("ok", ms <= BUDGET);
  verdictEl.classList.toggle("warn", ms > BUDGET);
}

function setQuality(q) {
  quality = q;
  nameEl.textContent = PRESETS[Math.round(q)].name;
  presetBtns.forEach((b, j) => b.classList.toggle("on", Math.round(q) === j));
  render();
}

scaleEl.addEventListener("input", () => { scale = +scaleEl.value; render(); });
presetBtns.forEach((b, j) => b.addEventListener("click", () => setQuality(j)));
setQuality(1);

// шум ±2% на fps — как у horizon-site, только без интервала при reduced-motion
// шум ±2% на fps, как на playhorizon.dev
if (!REDUCED) setInterval(() => {
  fpsEl.textContent = (fps(frameMs()) * (1 + (Math.random() * 2 - 1) * 0.02)).toFixed(0);
}, 550);
