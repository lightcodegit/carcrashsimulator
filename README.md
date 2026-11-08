# Car Crash Simulator

[![CI](https://github.com/lightcodegit/carcrashsimulator/actions/workflows/ci.yml/badge.svg)](https://github.com/lightcodegit/carcrashsimulator/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Godot 4.7.2](https://img.shields.io/badge/Godot-4.7.2%20stable-blue.svg)](https://godotengine.org/download/archive/)

3D-краш-песочница на Godot 4.7 (GL Compatibility, GDScript): кузов из CC0-моделей
мнётся вмятинами в точке удара, заезд сопровождает телеметрический HUD, а вокруг —
меню с живым 3D-миром под интерфейсом, гараж с тюнингом и окраской, настройки с
переназначением любых клавиш.

<p align="center">
  <img src="docs/images/crumple.jpg" width="32%" alt="Фотомод у стены: кузов смят в точке удара, слева — телеметрия, снизу — полоса фотомода">
  <img src="docs/images/garage.jpg" width="32%" alt="Гараж: зелёный седан в живом мире и панель тюнинга с окраской">
  <img src="docs/images/skid.jpg" width="32%" alt="Занос на арене: след резины остаётся на асфальте">
</p>

<p align="center"><sub>Смятие и фотомод · гараж с окраской · след резины в заносе. Кадры сняты
живым рендером GL Compatibility, 1600×900.</sub></p>

## Что в игре

- **Деформация кузова** — вершины меша смещаются вдоль вектора потери скорости:
  лобовой, боковой и кормовой удары мнут свой борт, вмятины накапливаются и
  сбрасываются рестартом.
- **5 машин** — от тяжёлого пикапа до «Машины бесконечности» без потолка скорости;
  у каждой паспортные vmax, масса, разгон и нитро.
- **6 карт** — испытательная арена, городок, трасса с финишной стеной, кольцевая
  гонка, бесконечная лента плит и большой город с районами.
- **Слоу-мо, реплей удара, фотомод** — повтор последних 10 секунд с перемоткой,
  свободная камера со снимками в PNG, ручное замедление времени.
- **Гараж** — жёсткость подвески, демпферы, тяга, тормоз, сцепление, бак нитро и
  окраска кузова; профиль на каждую машину хранится в `user://garage_v1.json`.
- **Звук и вибрация** — синтезированный DSP-мотор, визг резины, удар и нитро;
  геймпад вибрирует на ударе и заносе.
- **Интерфейс на русском и английском** — переключается в настройках на ходу;
  отладочный оверлей F2/F3 показывает телеметрию движка.

## Управление

| Действие | Клавиатура | Геймпад |
|---|---|---|
| Газ / тормоз | W / S | RT / LT |
| Руль | A/D, ←/→ | левый стик |
| Ручник / стояночный | Space | A (крестик) **или** L1 |
| Нитро (удержание) | Shift | R1 |
| Слоу-мо (удержание) | Ctrl | B |
| Камера (погоня → капот → орбита) | C | X |
| Рестарт | R | Y |
| Пауза | Esc | Start |

Все действия переопределяются в **НАСТРОЙКИ → УПРАВЛЕНИЕ** (из главного меню и из
паузы): клавиатура и геймпад хранятся раздельно, модификаторы (Ctrl, Shift, Alt,
Win) — часть назначения, `Ctrl+F` и `F` — две разные клавиши. Таблица выше —
раскладка по умолчанию.

## Запуск

1. Открой проект в Godot **4.7.2 stable** (не .NET), файл `project.godot`.
2. Нажми **F5** — игра запустится с меню.

### Windows / Linux: переносимые команды

Нужны **Node.js >=22** (без npm-зависимостей) и стандартный Godot **4.7.2 stable**.
Для экспорта установи шаблоны **4.7.2.stable** через
**Editor → Manage Export Templates** или из
[официального релиза](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable).
CI скачивает этот же редактор и шаблоны, проверяя SHA-256.

```sh
node tools/project.mjs --help
node tools/project.mjs import
node tools/project.mjs test
node tools/project.mjs build windows
node tools/project.mjs build linux
node tools/project.mjs run                 # открывает GUI, использует настройки игрока
```

Godot ищется в PATH как `godot`; можно задать переменную `GODOT` или добавить
`--godot "C:/path with spaces/Godot.exe"` к любой команде. `help <команда>` и
`<команда> --help` описывают опции. Import, test и build окон не открывают;
тесты гоняются параллельно (`--jobs N`, по умолчанию — половина ядер, потолок 4).

Сборка импортирует временную копию проекта с `tools/export_presets.cfg` и кладёт
релиз в `artifacts/build/{windows,linux}/` (бинарник **вместе с .pck**). Локальный
`export_presets.cfg` не читается и не перезаписывается. Логи и JSON-отчёты
каждого запуска — `artifacts/logs/` (игнорируется Git). CI проверяет обе ОС и
**обязательно запускает собранный билд** headless на несколько кадров:
«экспортировалось» без «запустилось» сборкой не считается. После скачивания
Linux-артефакта может понадобиться `chmod +x "Car Crash Simulator.x86_64"`.

### Готовые сборки

Играть без сборки из исходников можно со
[страницы релизов](https://github.com/lightcodegit/carcrashsimulator/releases):
каждая версия `v*` публикуется автоматически workflow-ом `Release` — два архива
(Windows и Linux x86_64) с бинарником и `.pck` внутри. Номер тега сверяется с
`application/config/version` в `project.godot` и с записью в `CHANGELOG.md`.

## Структура

```
assets/           CC0-модели Kenney Car Kit и Racing Kit + лицензии
scenes/           main_menu.tscn, game.tscn
scripts/core/     car_rig (VehicleBody3D), dent_body (деформация кузова),
                  materials, effects_director (частицы), camera_rig, skid_marks,
                  game_manager, vehicle_params, vehicle_db, garage_profiles,
                  audio_mixer + audio_driver (синтез звука), vibration_feed,
                  replay_recorder + replay_player, photo_mode, i18n
scripts/maps/     map_db (фасад), map_defs, map_kit, map_props, map_circuit
                  и по файлу на карту: arena / town / bigcity / speedway
scripts/ui/       ui_theme, main_menu, garage_panel, hud, settings_menu,
                  debug_overlay
scripts/autoload/ GameContext, TimeScale, InputRouter, Settings
tests/            d_* — data-тесты, h_* — интеграционные харнесы, p_* —
                  ручная диагностика и скриншот-раннеры
tools/            project.mjs — раннер импорта/тестов/сборки/запуска
```

## Тесты

```sh
node --test tools/project.test.mjs          # тесты самого раннера, Godot не нужен
node tools/project.mjs import              # сначала импортировать ресурсы и классы
node tools/project.mjs test --list
node tools/project.mjs test --test d_assets --test h_crash --timeout 180
node tools/project.mjs test                # весь автоматически найденный набор
node tools/project.mjs test --fail-on-skip  # строгий режим: partial/skip тоже ошибка
```

Раннер находит `tests/**/d_*.gd` и `tests/**/h_*.tscn`; `--test` принимает точные
имена из `--list`. Каждый тест получает изолированные `APPDATA`/`HOME`/`XDG_*`
в системном temp — настройки игрока и результаты соседних тестов не подменяют
дефолты. Успех требует строки `ALL PASS`, кода 0 и отсутствия `SCRIPT ERROR`/`FAIL`;
`PARTIAL`/`SKIP` считаются отдельно и не равны pass. Тесты, которым нужен живой
GPU, окно или геймпад, в headless честно сообщают partial либо помечены skipped —
полное их покрытие делается ручным прогоном с живым окном (`p_live_probe`).

## Лицензия

Код, сцены и тесты — под **MIT** (`LICENSE`). Ассеты — не наши: `assets/` это
CC0-наборы Kenney Car Kit и Racing Kit, их тексты лицензий лежат рядом с файлами
и входят в сборку, а проверка `d_assets` следит, чтобы не потерялись. Имена
«Godot» и «Kenney» — товарные знаки соответствующих владельцев, упомянуты только
чтобы объяснить, на чём сделано.

Если берёте проект к себе: MIT требует сохранить уведомление об авторстве,
CC0 не требует ничего, но сказать спасибо авторам наборов — хороший тон.
