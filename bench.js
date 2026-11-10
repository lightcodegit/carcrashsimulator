"use strict";
// Бенчмарк в духе horizon-site: ползунок лежит на шкале ЦЕНЫ КАДРА (мс),
// масштаб рендера выводится из неё. Модель: у пресета 61% цены не зависит от
// масштаба рендера, 39% растёт как (s/0.7)² — анкеры: геометрия 6.7 мс на 70%
// и 9.4 мс на 100% (замеры p_perf на Intel UHD 730).
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
      budgetEl = el("b-budget"), scaleEl = el("b-scale-readout"),
      qBtns = document.querySelectorAll("#b-presets button");

let preset = 1;      // индекс пресета
let ms = 13.7;       // цена кадра — значение ползунка (мс)
let scale = 0.7;     // выведенный масштаб рендера

const msAt = (p, s) => PRESETS[p].ms0 * (0.61 + 0.39 * Math.pow(s / 0.7, 2));
const scaleFor = (p, ms) =>
  clamp(0.7 * Math.sqrt(Math.max(0, (ms / PRESETS[p].ms0 - 0.61) / 0.39)), 0.5, 1);
const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

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

  // ползунок и заполнение — на одной шкале 0..OVERLOAD_MS
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
  scaleEl.textContent = "render scale " + Math.round(scale * 100) + "%";
  requestAnimationFrame(tick);
}
requestAnimationFrame(tick);

function syncRange() {
  rangeEl.min = "0";
  rangeEl.max = OVERLOAD_MS.toFixed(1);
  rangeEl.step = "0.1";
  rangeEl.value = ms.toFixed(1);
}

function setPreset(p) {
  preset = p;
  nameEl.textContent = NAMES[window.CCS_LANG || "en"][p];
  qBtns.forEach((b, j) => b.classList.toggle("on", j === p));
  // при смене пресета сохраняем масштаб рендера
  ms = clamp(msAt(p, scale), msAt(p, 0.5), msAt(p, 1.0));
  syncRange();
}

function syncName() {
  const i = clamp(Math.round(preset), 0, 3);
  nameEl.textContent = NAMES[window.CCS_LANG || "en"][i];
  qBtns.forEach((b, j) => b.classList.toggle("on", j === i));
}

rangeEl.addEventListener("input", () => {
  ms = clamp(+rangeEl.value, msAt(preset, 0.5), msAt(preset, 1.0));
  scale = scaleFor(preset, ms);
  syncRange();
});
qBtns.forEach((b, j) => b.addEventListener("click", () => {
  preset = j;
  ms = clamp(msAt(j, scale), msAt(j, 0.5), msAt(j, 1.0));
  syncRange();
}));
syncRange();
