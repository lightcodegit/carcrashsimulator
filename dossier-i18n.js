"use strict";
// Language catalog for the crash-dossier site. English first, Russian second:
// every visual string is here, the markup carries only keys.
const I18N = {
  en: {
    brand: "Car Crash Simulator",
    nav_log: "Crash log",
    nav_bench: "Benchmark",
    nav_screens: "Screens",
    nav_controls: "Controls",
    nav_download: "Download",

    hero_kicker: "Crash-test sandbox · Godot 4.7.2 · MIT + CC0",
    h1a: "Every dent",
    h1b: "is real.",
    hero_lede: "Speed up, hit anything — and the body crumples right at the point of impact. Telemetry, a 10-second impact replay, photo mode and a garage with tuning and paint, in one self-contained file per platform.",
    btn_dl: "Download v0.1.2",
    btn_src: "Source on GitHub",

    sp_engine: "Engine",
    sp_render: "Renderer",
    sp_render_v: "GL Compatibility",
    sp_cars: "Cars",
    sp_maps: "Maps",
    sp_build: "Build",
    sp_build_v: "1 file per platform",
    sp_price: "Price",
    sp_price_v: "free, open source",

    ev1: "Evidence 01 — frontal impact against a concrete wall · live frame",
    t1: "vertex deformation",
    t2: "10-second impact replay",
    t3: "photo mode",
    t4: "garage & paint",
    t5: "synth audio, no samples",
    t6: "gamepad rumble",
    t7: "5 cars",
    t8: "7 maps",
    t9: "rebindable controls",

    log_kick: "Section 01 — crash log",
    log_h2: "What actually happens<br>when you hit a wall.",
    f1: "Vertex deformation",
    f1b: "Vertices shift along the velocity-loss vector: head-on, side and rear impacts crumple their own panel. Dents accumulate, capped at 30% of the body height, and clear on a restart.",
    f2: "Impact replay",
    f2b: "The ring records 20 snapshots a second — chassis, wheels, nearby props and every dent as an event list. The replay plays the recording verbatim; nothing is re-simulated.",
    f3: "Garage & paint",
    f3b: "Suspension stiffness, dampers, thrust, brakes, grip and the nitro tank — one saved profile per car. Paint touches exactly the body cell of the texture atlas.",
    f4: "Audio & rumble",
    f4b: "Engine, tire squeal, nitro and impacts are synthesized live by a DSP mixer — no samples. The gamepad vibrates on impacts and slides.",
    f5: "Photo mode",
    f5b: "A free camera with WASD flight, zoom and PNG screenshots. Hide the whole interface with one key and frame the wreck like a studio shoot.",
    f6: "Full settings",
    f6b: "Image presets plus individual graphics options, slow-mo, two languages switchable on the fly, and rebindable controls — keyboard and gamepad stored separately.",

    bench_kick: "Section 02 — instrument panel",
    bench_comp: "composition.",

    bench_lede: "The measured frame cost of this effect composition, live rendering at 1600×900 on integrated graphics. Drag the slider to try your own frame budget.",
    bench_r1: "Effect composition",
    bench_r2: "Render scale",
    bench_r3: "Resulting frame rate",
    bench_note: "Live render at 1600×900 on Intel HD 630 integrated graphics · the game ships at 70% render scale.",
    v_fit: m => "fits 60 Hz — " + m + " fps",
    v_drop: m => "drops to 30 Hz — " + m + " fps",
    v_gpu: "needs a discrete GPU",
    scale_lbl: p => p + "%",
    ships70: "70% — as shipped",
    p0: "LOW", p1: "MEDIUM", p2: "HIGH", p3: "FILM",

    scr_kick: "Section 03 — evidence board",
    scr_h2: "Straight from the game.",
    ev2: "Evidence 02 — garage: tuning sliders and full body paint",
    ev3: "Evidence 03 — a slide leaves a skid mark that ages and fades",
    frames_h: "5 cars · 7 maps",
    frames_b: "From a heavy pickup to the Endless car with no speed cap — on a test arena, a town with parked cars, a drag strip, a race loop, an endless strip, the void plane and a big city with districts.",

    open_kick: "Section 04 — the open source",
    open_h2: "Built in the open.",
    open_lede: "Every line of the game is on GitHub under MIT, with CC0 assets. The test runner discovers the harnesses on its own, runs them with isolated player profiles and refuses a build that does not boot.",
    s1l: "automated checks",
    s2l: "fps measured, full pipeline",
    s3l: "cars / maps",
    s4l: "platforms shipped by CI",

    ctrl_h: "Controls — default layout",
    ctrl_sub: "everything rebindable in SETTINGS → CONTROLS · modifiers are part of the binding",
    ctrl_act: "Action",
    ctrl_kb: "Keyboard",
    ctrl_pad: "Gamepad",
    c1: "Throttle / Brake",
    c2: "Steering",
    c2p: "left stick",
    c3: "Handbrake",
    c4: "Nitro (hold)",
    c5: "Slow-mo (hold)",
    c6: "Camera: chase → hood → orbit",
    c7: "Restart",
    c8: "Pause",

    dl_kick: "Section 05 — pickup",
    dl_h2: "Download v0.1.2.",
    dl_win: "Windows",
    dl_win_sub: "x86_64 · Windows 10/11 · OpenGL 3.3 · ~38 MB",
    dl_linux: "Linux",
    dl_linux_sub: "x86_64 · glibc · X11 or Wayland · ~29 MB",
    dl_file: "ZIP archive from the latest release",
    dl_go: "Download ↓",
    req1: "The archive contains one self-contained file — game data is embedded into the executable.",
    req2: "Windows 10/11 or a glibc Linux distribution; GPU with OpenGL 3.3 — integrated graphics is fine at the default preset.",
    req3: "A gamepad is optional: vibration and full rebinding are supported.",
    req4: "~110 MB of disk space.",
    dl_note: "Building from source — Godot 4.7.2 (not .NET) and Node ≥ 22: <code>node tools/project.mjs build windows</code>. Other releases live on the <a href=\"https://github.com/lightcodegit/carcrashsimulator/releases\" target=\"_blank\" rel=\"noopener\">Releases</a> page.",

    foot_by: "Written by",
    foot_link: "crystaldev (@lightcodegit)",
    foot_assets: "assets are CC0 Kenney Car Kit and Racing Kit.",
    foot_tiny: "Godot is a trademark of the Godot Foundation; Kenney of Kenney.nl — mentioned only to say what this is built with.",
    totop: "↑ to the top",
  },

  ru: {
    brand: "Car Crash Simulator",
    nav_log: "Журнал удара",
    nav_bench: "Бенчмарк",
    nav_screens: "Скриншоты",
    nav_controls: "Управление",
    nav_download: "Загрузить",

    hero_kicker: "Краш-песочница · Godot 4.7.2 · MIT + CC0",
    h1a: "Каждая вмятина",
    h1b: "настоящая.",
    hero_lede: "Разгонись, ударь во что угодно — и кузов сомнётся ровно в точке удара. Телеметрия, 10-секундный повтор аварии, фотомод и гараж с тюнингом и окраской — один самодостаточный файл на платформу.",
    btn_dl: "Загрузить v0.1.2",
    btn_src: "Исходники на GitHub",

    sp_engine: "Движок",
    sp_render: "Рендерер",
    sp_render_v: "GL Compatibility",
    sp_cars: "Машины",
    sp_maps: "Карты",
    sp_build: "Сборка",
    sp_build_v: "1 файл на платформу",
    sp_price: "Цена",
    sp_price_v: "бесплатно, открытый код",

    ev1: "Улика 01 — лобовой удар в бетонную стену · живой кадр",
    t1: "деформация вершин",
    t2: "10-секундный повтор удара",
    t3: "фотомод",
    t4: "гараж и окраска",
    t5: "синтез звука, без сэмплов",
    t6: "вибрация геймпада",
    t7: "5 машин",
    t8: "7 карт",
    t9: "переназначение клавиш",

    log_kick: "Раздел 01 — журнал удара",
    log_h2: "Что на самом деле происходит,<br>когда врезаешься в стену.",
    f1: "Деформация вершин",
    f1b: "Вершины смещаются по вектору потери скорости: лобовой, боковой и кормовой удары мнут свой борт. Вмятины копятся, до 30% высоты кузова, и сбрасываются рестартом.",
    f2: "Повтор удара",
    f2b: "Кольцо пишет 20 кадров в секунду — шасси, колёса, предметы вокруг и каждую вмятину отдельным событием. Повтор проигрывает запись дословно — досчёта физики нет.",
    f3: "Гараж и окраска",
    f3b: "Жёсткость подвески, демпферы, тяга, тормоз, сцепление и бак нитро — один сохранённый профиль на машину. Окраска трогает ровно ячейку кузова атласа.",
    f4: "Звук и вибрация",
    f4b: "Мотор, визг резины, нитро и удары синтезирует DSP-микшер живьём — без сэмплов. Геймпад вибрирует на ударах и заносах.",
    f5: "Фотомод",
    f5b: "Свободная камера: полёт на WASD, зум и снимки в PNG. Спрячь весь интерфейс одной клавишей и снимай разбитую машину как в студии.",
    f6: "Полные настройки",
    f6b: "Пресеты картинки плюс отдельные графические опции, слоу-мо, два языка с переключением на лету и переназначение управления — клавиатура и геймпад хранятся отдельно.",

    bench_kick: "Раздел 02 — приборная панель",
    bench_comp: "пресет.",
    bench_lede: "Замеренная цена кадра этой композиции эффектов, живой рендер на 1600×900 на встроенной графике. Двигай ползунок, чтобы попробовать свой бюджет кадра.",
    bench_r1: "Состав эффектов",
    bench_r2: "Масштаб рендера",
    bench_r3: "Итоговая частота кадров",
    bench_note: "Живой рендер на 1600×900 на встроенной графике Intel HD 630 · игра поставляется на масштабе 70%.",
    v_fit: m => "укладывается в 60 Гц — " + m + " fps",
    v_drop: m => "падает до 30 Гц — " + m + " fps",
    v_gpu: "нужна дискретная видеокарта",
    scale_lbl: p => p + "%",
    ships70: "70% — как в игре",
    p0: "НИЗКИЙ", p1: "СРЕДНИЙ", p2: "ВЫСОКИЙ", p3: "ФИЛЬМ",

    scr_kick: "Раздел 03 — доска улик",
    scr_h2: "Прямо из игры.",
    ev2: "Улика 02 — гараж: ползунки тюнинга и полная окраска",
    ev3: "Улика 03 — занос оставляет след резины, который стареет и гаснет",
    frames_h: "5 машин · 7 карт",
    frames_b: "От тяжёлого пикапа до Endless-машины без предела скорости — на тестовой арене, в городе с припаркованными машинами, на драг-стрипе, гоночном кольце, бесконечной ленте, пустоте и в большом городе с районами.",

    open_kick: "Раздел 04 — открытый код",
    open_h2: "Всё в открытом коде.",
    open_lede: "Каждая строка игры на GitHub под MIT, ассеты под CC0. Раннер тестов сам находит харнесы, гоняет их с изолированным профилем игрока и не принимает сборку, которая не запускается.",
    s1l: "автоматических проверок",
    s2l: "fps на полном пайплайне",
    s3l: "машин / карт",
    s4l: "платформы собирает CI",

    ctrl_h: "Управление — раскладка по умолчанию",
    ctrl_sub: "всё переназначается в НАСТРОЙКИ → УПРАВЛЕНИЕ · модификаторы часть бинда",
    ctrl_act: "Действие",
    ctrl_kb: "Клавиатура",
    ctrl_pad: "Геймпад",
    c1: "Газ / Тормоз",
    c2: "Руль",
    c2p: "левый стик",
    c3: "Ручник",
    c4: "Нитро (держать)",
    c5: "Слоу-мо (держать)",
    c6: "Камера: погоня → капот → орбита",
    c7: "Рестарт",
    c8: "Пауза",

    dl_kick: "Раздел 05 — выдача",
    dl_h2: "Загрузить v0.1.2.",
    dl_win: "Windows",
    dl_win_sub: "x86_64 · Windows 10/11 · OpenGL 3.3 · ~38 МБ",
    dl_linux: "Linux",
    dl_linux_sub: "x86_64 · glibc · X11 или Wayland · ~29 МБ",
    dl_file: "ZIP-архив из последнего релиза",
    dl_go: "Загрузить ↓",
    req1: "В архиве один самодостаточный файл — данные игры встроены в исполняемый файл.",
    req2: "Windows 10/11 или glibc-дистрибутив Linux; GPU с OpenGL 3.3 — встроенной графики достаточно на дефолтном пресете.",
    req3: "Геймпад необязателен: поддержаны вибрация и полное переназначение.",
    req4: "~110 МБ на диске.",
    dl_note: "Сборка из исходников — Godot 4.7.2 (не .NET) и Node ≥ 22: <code>node tools/project.mjs build windows</code>. Прочие релизы — на странице <a href=\"https://github.com/lightcodegit/carcrashsimulator/releases\" target=\"_blank\" rel=\"noopener\">Releases</a>.",

    foot_by: "Автор —",
    foot_link: "crystaldev (@lightcodegit)",
    foot_assets: "ассеты — CC0 Kenney Car Kit и Racing Kit.",
    foot_tiny: "Godot — товарный знак Godot Foundation; Kenney — Kenney.nl: упомянуты, чтобы объяснить, на чём сделана игра.",
    totop: "↑ наверх",
  },
};

let lang = localStorage.getItem("ccs-lang") || "en";
if (lang !== "ru" && lang !== "en") lang = "en";
window.CCS_LANG = lang;
window.CCS_I18N = I18N;

function applyLang() {
  const dict = I18N[lang];
  document.documentElement.lang = lang;
  document.querySelectorAll("[data-i18n]").forEach(el => {
    const v = dict[el.getAttribute("data-i18n")];
    if (v != null) el.textContent = v;
  });
  document.querySelectorAll("[data-i18n-html]").forEach(el => {
    const v = dict[el.getAttribute("data-i18n-html")];
    if (v != null) el.innerHTML = v;
  });
  const btn = document.getElementById("lang-btn");
  if (btn) btn.textContent = lang === "en" ? "RU" : "EN";
  if (window.ccsRefreshBench) window.ccsRefreshBench();
}

function setLang(l) {
  lang = l;
  window.CCS_LANG = l;
  localStorage.setItem("ccs-lang", l);
  applyLang();
}

document.addEventListener("DOMContentLoaded", () => {
  const btn = document.getElementById("lang-btn");
  if (btn) btn.addEventListener("click", () => setLang(lang === "en" ? "ru" : "en"));
  applyLang();
});
