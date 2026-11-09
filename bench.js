"use strict";
// Бенчмарк: два независимых ползунка (состав эффектов + масштаб рендера),
// цена кадра считается по модели с анкерами p_perf:
// ms(q, s) = ms0(q) · (0.61 + 0.39·(s/0.7)²), где ms0(q) — линейная интерполяция
// между измеренными пресетами 6.7 / 13.7 / 29.4 / 29.2 мс на Intel UHD 730.
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
  en: { fit: m => "fits 60 Hz — " + m + " fps", drop: m => "drops to 30 Hz — " + m + " fps", gpu: "needs a discrete GPU" },
  ru: { fit: m => "укладывается в 60 Гц — " + m + " fps", drop: m => "падает до 30 Гц — " + m + " fps", gpu: "нужна дискретная видеокарта" },
};

const el = id => document.getElementById(id);
const msEl = el("b-ms"), fpsEl = el("b-fps"), nameEl = el("b-name"),
      verdictEl = el("b-verdict"), qEl = el("b-q"), qFillEl = el("b-qfill"),
      sEl = el("b-s"), sFillEl = el("b-sfill"),
      qBarEl = qFillEl.parentElement, sBarEl = sFillEl.parentElement,
      fpsBarEl = el("b-fpsfill").parentElement;
const qBtns = document.querySelectorAll("#b-presets button");

let q = 1, s = 0.7;

const ms0 = x => {
  const i = clamp(Math.floor(x), 0, 2);
  return PRESETS[i].ms0 + (PRESETS[i + 1].ms0 - PRESETS[i].ms0) * (x - i);
};
const msOf = (x, sc) => ms0(x) * (0.61 + 0.39 * Math.pow(sc / 0.7, 2));
const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

let shownMs = msOf(q, s), shownFps = 1000 / shownMs;
function tick() {
  const targetMs = msOf(q, s), targetFps = 1000 / targetMs;
  const k = REDUCED ? 1 : 0.22;
  shownMs += (targetMs - shownMs) * k;
  shownFps += (targetFps - shownFps) * k;
  msEl.textContent = shownMs.toFixed(1);
  fpsEl.textContent = String(Math.round(shownFps));

  const over = targetMs > OVERLOAD_MS;
  const amp = 0.4 + clamp((targetMs - OVERLOAD_MS) / (OVERLOAD_MS - BUDGET), 0, 1) * 2.2;
  for (const bar of [qBarEl, sBarEl, fpsBarEl]) {
    bar.classList.toggle("overload", over && !REDUCED);
    bar.style.setProperty("--amp", amp.toFixed(2));
  }
  msEl.style.color = targetMs <= BUDGET ? "" : "var(--hot)";
  fpsEl.style.color = targetMs <= BUDGET ? "" : "var(--hot)";

  qFillEl.style.width = (clamp(q, 0, 3) / 3 * 100) + "%";
  sFillEl.style.width = ((clamp(s, 0.5, 1) - 0.5) / 0.5 * 100) + "%";
  fpsBarEl.querySelector(".fill").style.width =
    (clamp(1000 / targetMs, 0, 120) / 120 * 100) + "%";

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
  requestAnimationFrame(tick);
}
requestAnimationFrame(tick);

function setPreset(i) {
  q = i;
  s = clamp(s, 0.5, 1);
  nameEl.textContent = NAMES[window.CCS_LANG || "en"][i];
  qBtns.forEach((b, j) => b.classList.toggle("on", j === i));
  qEl.value = String(q * 100);
  sEl.value = String(s * 100);
}
function syncName() {
  const i = clamp(Math.round(q), 0, 3);
  nameEl.textContent = NAMES[window.CCS_LANG || "en"][i];
  qBtns.forEach((b, j) => b.classList.toggle("on", j === i));
}
qEl.addEventListener("input", () => { q = +qEl.value / 100; syncName(); });
sEl.addEventListener("input", () => { s = +sEl.value / 100; });
qBtns.forEach((b, j) => b.addEventListener("click", () => setPreset(j)));
window.ccsRefreshBench = () => { nameEl.textContent = NAMES[window.CCS_LANG || "en"][Math.round(q)]; };
setPreset(1);
