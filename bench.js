"use strict";
// Benchmark: the slider sits on the frame-cost scale (ms) and render scale is
// derived from it. Model: 61% of a preset's cost is resolution-independent, 39%
// scales as (s/0.7)^2 - anchors: 6.7 ms geometry at 70% and 9.4 ms at 100%
// (p_perf measurements on Intel UHD 730).
const PRESETS = [
  { name: "LOW", ms0: 6.7 },
  { name: "MEDIUM", ms0: 13.7 },
  { name: "HIGH", ms0: 29.4 },
  { name: "FILM", ms0: 29.2 },
];
const BUDGET = 16.7;
const OVERLOAD_MS = 33.4;
const REDUCED = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
const NAMES = {
  en: ["LOW", "MEDIUM", "HIGH", "FILM"],
  ru: ["НИЗКИЙ", "СРЕДНИЙ", "ВЫСОКИЙ", "КИНО"],
};
const SCALE_LABEL = {
  en: pct => "render scale " + pct + "%",
  ru: pct => "масштаб рендера " + pct + "%",
};
const VERDICT = {
  en: {
    fit: m => "fits 60 Hz — " + m + " fps",
    drop: m => "drops to 30 Hz — " + m + " fps",
    gpu: "needs a discrete GPU",
  },
  ru: {
    fit: m => "укладывается в 60 Гц — " + m + " fps",
    drop: m => "падает до 30 Гц — " + m + " fps",
    gpu: "нужна дискретная видеокарта",
  },
};

const el = id => document.getElementById(id);
const msEl = el("b-ms"), fpsEl = el("b-fps"), nameEl = el("b-name"),
      verdictEl = el("b-verdict"), rangeEl = el("b-ms-range"),
      fillEl = el("b-fill"), fpsFillEl = el("b-fpsfill"),
      scaleEl = el("b-scale-readout"),
      qBtns = document.querySelectorAll("#b-presets button");

let preset = 1;      // preset index
let ms = 13.7;       // frame cost - slider value (ms)
let scale = 0.7;     // derived render scale

const msAt = (p, s) => PRESETS[p].ms0 * (0.61 + 0.39 * Math.pow(s / 0.7, 2));
const scaleFor = (p, v) =>
  clamp(0.7 * Math.sqrt(Math.max(0, (v / PRESETS[p].ms0 - 0.61) / 0.39)), 0.5, 1);
const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
const msBounds = p => [msAt(p, 0.5), Math.min(msAt(p, 1.0), OVERLOAD_MS)];

let shownMs = ms, shownFps = 1000 / ms;
function tick() {
  const targetMs = ms, targetFps = 1000 / targetMs;
  const k = REDUCED ? 1 : 0.22;
  shownMs += (targetMs - shownMs) * k;
  shownFps += (targetFps - shownFps) * k;
  msEl.textContent = shownMs.toFixed(1);
  fpsEl.textContent = String(Math.round(shownFps));

  const over = targetMs > OVERLOAD_MS;
  const amp = 0.4 + clamp((targetMs - OVERLOAD_MS) / (OVERLOAD_MS - BUDGET), 0, 1) * 2.2;
  for (const bar of [fillEl.parentElement, fpsFillEl.parentElement]) {
    bar.classList.toggle("overload", over && !REDUCED);
    bar.style.setProperty("--amp", amp.toFixed(2));
  }
  msEl.style.color = targetMs <= BUDGET ? "" : "var(--hot)";
  fpsEl.style.color = targetMs <= BUDGET ? "" : "var(--hot)";

  // slider and fill share the 0..OVERLOAD_MS scale
  const pos = clamp(targetMs / OVERLOAD_MS * 100, 0, 100);
  fillEl.style.width = pos.toFixed(1) + "%";
  fpsFillEl.style.width = clamp(1000 / targetMs / 120 * 100, 2, 100).toFixed(1) + "%";

  const v = VERDICT[window.CCS_LANG || "en"];
  if (targetMs <= BUDGET) {
    verdictEl.textContent = v.fit(Math.round(targetFps));
    verdictEl.classList.remove("warn");
  } else if (targetMs <= OVERLOAD_MS) {
    verdictEl.textContent = v.drop(Math.round(targetFps));
    verdictEl.classList.add("warn");
  } else {
    verdictEl.textContent = v.gpu;
    verdictEl.classList.add("warn");
  }
  const sl = SCALE_LABEL[window.CCS_LANG || "en"];
  scaleEl.textContent = sl(Math.round(scale * 100));
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

function setPreset(p) {
  preset = p;
  const [lo, hi] = msBounds(p);
  // preserve render scale when switching presets
  ms = clamp(msAt(p, scale), lo, hi);
  syncRange();
  syncName();
}

function syncName() {
  const lang = window.CCS_LANG || "en";
  nameEl.textContent = NAMES[lang][preset];
  qBtns.forEach((b, j) => {
    b.classList.toggle("on", j === preset);
    b.textContent = NAMES[lang][j];
  });
}

rangeEl.addEventListener("input", () => {
  const [lo, hi] = msBounds(preset);
  ms = clamp(+rangeEl.value, lo, hi);
  scale = scaleFor(preset, ms);
  syncRange();
});
qBtns.forEach((b, j) => b.addEventListener("click", () => setPreset(j)));

// Called by i18n.js after language changes.
window.ccsRefreshBench = syncName;
syncRange();
syncName();
