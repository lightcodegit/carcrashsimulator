const I18N = {
  en: {
    nav_features: "Features", nav_screens: "Screens", nav_bench: "Benchmarks",
    nav_about: "About", nav_source: "Source", nav_download: "Download",
    kicker: "Godot 4.7 · Written in GDScript · Free, MIT + CC0",
    h1_1: "The sandbox where", h1_2: "every dent is real.",
    lede: "Speed up, hit anything and the car body crumples right at the point of impact. Telemetry, a 10-second impact replay, photo mode and a garage with tuning and paint — one file per platform.",
    download: "Download v0.1.1", source: "View on GitHub",
    tick1: "Real vertex deformation", tick2: "Impact replay from a recorded ring",
    tick3: "Gamepad with rumble, keyboard and mouse",
    features_h2: "Five cars. Seven maps. One file per platform.",
    f1: "Deformation without simulation",
    f1b: "Vertices shift along the velocity-loss vector: head-on, side and rear impacts crumple their own panel. Dents accumulate, capped at 30% of the body height, and clear on a restart.",
    f2: "Impact replay",
    f2b: "The ring records 20 snapshots a second — chassis, wheels, nearby props and every dent as an event list the player replays verbatim.",
    f3: "Garage with paint",
    f3b: "Suspension, dampers, thrust, brakes, grip and the nitro tank — one saved profile per car, written atomically. Paint touches exactly the body cell of the texture atlas.",
    f4: "Sound and rumble",
    f4b: "Engine, tire squeal, nitro and impacts are synthesized live by a DSP mixer — no samples. The gamepad vibrates on impacts and slides.",
    f5: "Photo mode",
    f5b: "A free camera with zoom and WASD flight. Hide the whole interface with one key and shoot the wreck as a PNG.",
    f6: "Two languages",
    f6b: "English and Russian, switchable on the fly — every string in the interface, including the debug overlay, is localized.",
    screens_h2: "Screens",
    cap1: "Thrust, brakes, suspension — and full body paint, saved per car.",
    cap2: "Tire marks age on the asphalt and fade out on their own.",
    open_h2: "Built in the open.",
    open_lede: "Every line of the game is on GitHub under MIT, with CC0 assets. The test runner discovers the harnesses on its own, runs them with isolated player profiles and refuses a build that does not boot.",
    s1: "68", s1l: "automated checks", s2: "148", s2l: "fps measured, full pipeline",
    s3: "2", s3l: "platforms shipped by CI", s4: "1", s4l: "file per platform",
    contrib: "Visit contributors",
    bench_label: "Benchmarks", bench_comp: "composition.",
    bench_r1: "Effect composition", bench_60: "60 Hz budget",
    bench_lede: "The measured frame cost of this preset composition, live rendering at 1600×900. Drag the sliders to try your own frame budget.",
    bench_r1: "Effect composition", bench_r2: "Render scale",
    bench_r3: "Resulting frame rate",
    v_fit: "fits 60 Hz — ", v_30: "drops to 30 Hz — ", v_gpu: "needs a discrete GPU",
    bench_note: "The model is anchored to the measured presets from the game's own test runner (p_perf, live rendering at 1600×900 on Intel UHD 730). Results vary with hardware.",
    p0: "LOW", p1: "MEDIUM", p2: "HIGH", p3: "FILM",
    dl_h2: "Download v0.1.1",
    dl_win: "Windows", dl_win_sub: "x86_64 · Windows 10/11 · OpenGL 3.3 · 38 MB zip",
    dl_linux: "Linux", dl_linux_sub: "x86_64 · glibc · X11 or Wayland · 29 MB zip",
    dl_note: "Each build is a single self-contained file — the game data is embedded into the executable. Building from source:",
    req_h2: "Requirements",
    req1: "Windows 10/11 or a glibc Linux distribution",
    req2: "A GPU with OpenGL 3.3 — integrated graphics is fine at the default preset",
    req3: "A gamepad is optional: vibration and rebinding are supported",
    req4: "~110 MB of disk — the game is one self-contained file",
    foot_by: "Written by ", foot_code: "Code under ", foot_assets: "assets are CC0 Kenney Car Kit and Racing Kit.",
    foot_by_link: "crystaldev (@lightcodegit)", foot_code_link: "MIT",
    foot_assets_link: "Kenney",
    foot_tiny: "Godot is a trademark of the Godot Foundation; Kenney of Kenney.nl — mentioned only to say what this is built with.",
  },
  ru: {
    nav_features: "Возможности", nav_screens: "Скриншоты", nav_bench: "Бенчмарк",
    nav_about: "О проекте", nav_source: "Исходники", nav_download: "Загрузить",
    kicker: "Godot 4.7 · Написана на GDScript · Бесплатно, MIT + CC0",
    h1_1: "Песочница, где", h1_2: "каждая вмятина настоящая.",
    lede: "Разгонись, ударь во что угодно — и кузов сомнётся ровно в точке удара. Телеметрия, 10-секундный повтор аварии, фотомод и гараж с тюнингом и окраской — один файл на платформу.",
    download: "Загрузить v0.1.1", source: "Исходники на GitHub",
    tick1: "Настоящая деформация вершин", tick2: "Повтор по записанному кольцу кадров",
    tick3: "Геймпад с вибрацией, клавиатура и мышь",
    features_h2: "Пять машин. Семь карт. Один файл на платформу.",
    f1: "Деформация без симуляции",
    f1b: "Вершины смещаются по вектору потери скорости: лобовой, боковой и кормовой удары мнут свой борт. Вмятины копятся (до 30% высоты кузова) и сбрасываются рестартом.",
    f2: "Повтор удара",
    f2b: "Кольцо пишет 20 кадров в секунду — шасси, колёса, предметы вокруг и каждую вмятину отдельным событием, которое плеер проигрывает дословно.",
    f3: "Гараж с окраской",
    f3b: "Жёсткость подвески, демпферы, тяга, тормоз, сцепление и бак нитро — один сохранённый профиль на машину, атомарная запись. Окраска трогает ровно ячейку кузова атласа.",
    f4: "Звук и вибрация",
    f4b: "Мотор, визг резины, нитро и удары синтезирует DSP-микшер — без сэмплов. Геймпад вибрирует на ударах и заносах.",
    f5: "Фотомод",
    f5b: "Свободная камера с зумом и полётом на WASD. Спрячь весь интерфейс одной клавишей и снимай разбитую машину как в студии.",
    f6: "Два языка",
    f6b: "Английский и русский, переключаются на лету — локализована каждая строка интерфейса, включая отладочный оверлей.",
    screens_h2: "Скриншоты",
    cap1: "Тяга, тормоз, подвеска — и полная окраска кузова, профиль на каждую машину.",
    cap2: "Следы резины стареют на асфальте и исчезают сами.",
    open_h2: "Всё в открытом коде.",
    open_lede: "Каждая строка игры на GitHub под MIT, ассеты под CC0. Раннер тестов сам находит харнесы, гоняет их с изолированным профилем игрока и не принимает сборку, которая не запускается.",
    s1: "68", s1l: "автоматических проверок", s2: "148", s2l: "fps на полном пайплайне",
    s3: "2", s3l: "платформы собирает CI", s4: "1", s4l: "файл на платформу",
    contrib: "Граф контрибьюторов",
    bench_label: "Бенчмарк",
    bench_lede: "Замеренная цена кадра этой композиции, живой рендер на 1600×900. Двигай ползунки, чтобы попробовать свой бюджет кадра.",
    bench_r1: "Состав эффектов", bench_r2: "Масштаб рендера",
    bench_r3: "Итоговый кадр",
    v_fit: "укладывается в 60 Гц — ", v_30: "падает до 30 Гц — ", v_gpu: "нужна дискретная видеокарта",
    bench_note: "Модель пришвартована к замерам пресетов из собственного раннера игры (p_perf, живой рендер на 1600×900 на Intel UHD 730). Результат зависит от железа.",
    p0: "НИЗКИЙ", p1: "СРЕДНИЙ", p2: "ВЫСОКИЙ", p3: "КИНО",
    dl_h2: "Загрузка v0.1.1",
    dl_win: "Windows", dl_win_sub: "x86_64 · Windows 10/11 · OpenGL 3.3 · zip 38 МБ",
    dl_linux: "Linux", dl_linux_sub: "x86_64 · glibc · X11 или Wayland · zip 29 МБ",
    dl_note: "Каждая сборка — один самодостаточный файл: данные игры встроены в исполняемый файл. Сборка из исходников:",
    req_h2: "Требования",
    req1: "Windows 10/11 или glibc-дистрибутив Linux",
    req2: "GPU с OpenGL 3.3 — встроенной графики достаточно на дефолтном пресете",
    req3: "Геймпад необязателен: поддержаны вибрация и переназначение",
    req4: "~110 МБ на диске — игра это один самодостаточный файл",
    foot_by: "Автор — ", foot_code: "Код под ", foot_assets: "ассеты — CC0 Kenney Car Kit и Racing Kit.",
    foot_by_link: "crystaldev (@lightcodegit)", foot_code_link: "MIT",
    foot_assets_link: "Kenney",
    foot_tiny: "Godot — товарный знак Godot Foundation; Kenney — Kenney.nl: упомянуты, чтобы объяснить, на чём сделана игра.",
  },
};

let lang = localStorage.getItem("ccs-lang") || "en";
if (lang !== "ru" && lang !== "en") lang = "en";
window.CCS_LANG = lang;

function applyLang() {
  const dict = I18N[lang];
  document.documentElement.lang = lang;
  document.querySelectorAll("[data-i18n]").forEach(el => {
    const key = el.getAttribute("data-i18n");
    if (dict[key] != null) el.textContent = dict[key];
  });
  document.querySelectorAll("[data-i18n-html]").forEach(el => {
    const key = el.getAttribute("data-i18n-html");
    if (dict[key] != null) el.innerHTML = dict[key];
  });
  const btn = document.getElementById("lang-btn");
  if (btn) btn.textContent = lang === "en" ? "RU" : "EN";
  if (window.ccsRefreshBench) window.ccsRefreshBench();
}
document.getElementById("lang-btn").addEventListener("click", () => setLang(lang === "en" ? "ru" : "en"));
function setLang(l) {
  lang = l; window.CCS_LANG = l;
  localStorage.setItem("ccs-lang", l);
  applyLang();
}
applyLang();
