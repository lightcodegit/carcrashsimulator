"use strict";
// Бенчмарк в духе horizon-site: ползунок лежит на шкале ЦЕНЫ КАДРА (мс),
// масштаб рендера выводится из неё. Модель: у каждого пресета 61% цены кадра
// не зависит от масштаба рендера, 39% растёт как (s/0.7)² — анкеры: геометрия
// 6.7 мс на 70% и 9.4 мс на 100% (замеры p_perf на Intel UHD 730).
const PRESETS = [
  { name: "LOW",    ms0: 6.7 },
  { name: "MEDIUM", ms0: 13.7 },
  { name: "HIGH",   ms0: 29.4 },
  { name: "FILM",   ms0: 29.2 }
];
const BUDGET = 16.7;
const MS_MAX = 45;                     // правый край шкалы цены кадра
const OVERLOAD_MS = 33.4;              // двойной бюджет 60 Гц: ниже — 30 fps
const REDUCED = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

const el = id => document.getElementById(id);
const msEl = el("b-ms"), nameEl = el("b-name"), fillEl = el("b-fill"),
      fpsEl = el("b-fps"), fpsFillEl = el("b-fpsfill"), verdictEl = el("b-verdict"),
      barEl = el("b-bar"), scaleEl = el("b-scale"),
      presetBtns = document.querySelectorAll("#b-presets button"),
      scaleReadout = el("b-scale-readout");

let preset = 1;   // индекс пресета
let ms = 0;       // текущая цена кадра — ЗНАЧЕНИЕ ПОЛЗУНКА
let scale = 0.7;  // масштаб рендера, выводится из цены кадра

const msAt = (p, s) => PRESETS[p].ms0 * (0.61 + 0.39 * Math.pow(s / 0.7, 2));
const MS_MIN = () => msAt(preset, 0.5);   // масштаб 50%
const MS_MAX_AT = () => msAt(preset, 1.0); // масштаб 100%
const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

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
  const lo = MS_MIN(), hi = MS_MAX_AT();
  const f = 1000 / ms;
  // ползунок и заполнение живут на одной шкале: позиция = (ms - lo)/(hi - lo)
  const pos = clamp((ms - lo) / (hi - lo), 0, 1);
  countUp(msEl, ms, 1);
  countUp(fpsEl, f, 0);
  fillEl.style.width = (pos * 100).toFixed(1) + "%";
  fillEl.style.background = ms <= BUDGET ? "var(--amber)" : "var(--hot)";
  fpsFillEl.style.width = clamp(f / 120 * 100, 2, 100) + "%";
  barEl.classList.toggle("over", ms > BUDGET);
  barEl.classList.toggle("overload", ms > OVERLOAD_MS);
  overload = clamp((ms - BUDGET) / (OVERLOAD_MS - BUDGET), 0, 1);
  barEl.style.setProperty("--amp", (0.4 + overload * 2.2).toFixed(2));
  barEl.style.setProperty("--shake", Math.max(0.12, 0.24 - overload * 0.1).toFixed(2) + "s");
  verdictEl.textContent = ms <= BUDGET ? "fits 60 Hz"
    : ms <= OVERLOAD_MS ? "drops to 30 Hz" : "needs a discrete GPU";
  verdictEl.classList.toggle("ok", ms <= BUDGET);
  verdictEl.classList.toggle("warn", ms > BUDGET);
  budgetEl.style.left = clamp((BUDGET - lo) / (hi - lo) * 100, 0, 100).toFixed(1) + "%";
  scale = 0.7 * Math.sqrt(Math.max(0, (ms / PRESETS[preset].ms0 - 0.61) / 0.39));
  scaleReadout.textContent = "render scale " + Math.round(scale * 100) + "%";
}

function syncRange() {
  const lo = MS_MIN(), hi = MS_MAX_AT();
  scaleEl.min = lo.toFixed(2);
  scaleEl.max = hi.toFixed(2);
  scaleEl.step = 0.05;
  scaleEl.value = ms.toFixed(2);
}

function setPreset(p) {
  preset = p;
  nameEl.textContent = PRESETS[p].name;
  presetBtns.forEach((b, j) => b.classList.toggle("on", j === p));
  // при смене пресета сохраняем ТЕКУЩИЙ масштаб рендера
  ms = clamp(msAt(p, scale), loScale(p), hiScale(p));
  syncRange();
  render();
}
function loScale(p) { return msAt(p, 0.5); }
function hiScale(p) { return msAt(p, 1.0); }

function loScale(p) { return msAt(p, 0.5); }
function hiScale(p) { return msAt(p, 1.0); }

scaleEl.addEventListener("input", () => { ms = +scaleEl.value; render(); });
presetBtns.forEach((b, j) => b.addEventListener("click", () => setPreset(j)));

ms = msAt(1, 0.7);
syncRange();
render();
