# Car Crash Simulator — инструкции для агентов

Godot 4.7.2 (standard, **не** .NET), GL Compatibility, GDScript. Продуктовая
архитектура и игровые числа — в `README.md`, он источник правды; здесь только то,
что меняет решение агента в этом репозитории.

## Команды

```sh
node --test tools/project.test.mjs                                  # тесты самого раннера, Godot не нужен
node tools/project.mjs import   --godot C:/Users/user/Desktop/Godot.exe
node tools/project.mjs test     --godot C:/Users/user/Desktop/Godot.exe --timeout 400
node tools/project.mjs test     --godot C:/Users/user/Desktop/Godot.exe --test h_audio --test d_params
node tools/project.mjs build    windows --godot C:/Users/user/Desktop/Godot.exe
node tools/project.mjs run      --godot C:/Users/user/Desktop/Godot.exe
```

- `import` обязателен после добавления или переименования `.gd`/`.tscn`: без него
  классы и сцены не видны тестам, и провал выглядит как «не существует функция».
- Редактор на этой машине лежит в `Desktop\Godot.exe` и **не в PATH** — путь всегда
  передавать `--godot` (или `GODOT`).
- Текущая база: 63 теста → 51 pass / 8 partial / 4 skipped / 0 failed. Любое
  изменение, поднявшее `failed` или уронившее найденное количество, — регресс.
- Логи и JSON-отчёты: `artifacts/logs/<затом>/<тест>/` (в git не попадают).

## Правила, которые уже спасали время

- **Тест обязан уметь падать.** Зелёный `ALL PASS` из таймаута, self-counting
  цикла, невызванного `await` или обхода «пусто ⇒ нечего проверять» — дефект.
  Новая проверка подтверждается мутацией: вернуть старое поведение → получить
  `FAIL` → откатить. Откаты делать правкой текста, а не копией файла из
  `tmp/` более раннего этапа.
- `PARTIAL`/`SKIP` — не `pass`: `PARTIAL` печатается только когда часть
  действительно не проверена (условие, а не оговорка), `NOTE` — информация.
  Строки вида «в headless звук не проверить» обязаны быть условными: в живом
  окне GPU и аудио есть, и врать в отчёте нельзя (см. `h_garage`).
- Тесты пишут в **настоящий** `user://`. Раннер изолирует его через `APPDATA`
  (`--user-dir` в этой сборке не работает); ручной запуск `Godot.exe` без
  `APPDATA=<пустая папка>` портит сохранённый конфиг игрока.
- Headless-ловушки, проверенные на себе: viewport 0×0 или квадратный (брать
  фактический размер, а не 1600×900 из `project.godot`), синтетические клики
  мышью не маршрутизируются в GUI (кнопки дёргать сигналом `pressed`),
  `Performance` по времени физики отдаёт 0, `AudioServer.get_driver_name() == "Dummy"`.

## Границы кода

- `scripts/maps/map_db.gd` — только фасад (`ids`/`build`/`recycle`/`debug_counts`).
  Геометрия живёт в `map_kit`, `map_props`, `map_circuit`, `map_<карта>`; числа и
  палитра — в `map_defs`. Не возвращать код карт в фасад.
- Аудио: генератор **не создаётся**, если дровейвер `Dummy` (`AudioDriver.has_output_device()`),
  и вывод один на процесс — освобождение `AudioStreamGenerator` вместе с деревом
  заезда давало access violation. Не заводить второй плеер на сцену и не освобождать
  хост в `_exit_tree` чужим экземпляром.
- Частицы — только `CPUParticles3D` (headless обязан считать то же, что окно), и
  эммитеры дыманаращиваются на `EffectsDirector`, а не на `VehicleWheel3D`: колесо
  освобождается вместе с машиной, активный эммитер на этом освободении обрывал процесс.
- Гараж: `brake_decel` обрезан физикой (`CarRig.BRAKE_MAX_G`), из `LIMITS` масштабируется
  только `accel_max` (`RELATIVE`) — иначе у ползунка появляется мёртвая зона. Окраска
  трогает ровно ячейку кузова атласа Kenney; `user://garage_v1.json` версионирован и
  пишется атомарно.
- UI: размеры через `UiTheme.fx()`/`px()`/`step()`, активные состояния через
  `UiTheme.nav_mark_active`. Пиксельные константы в код UI не вносить — ступенчатый
  рост интерфейса их ломает.
- Реплей проигрывает записанное, а не пересимулирует: мир на паузе, поза и скорость
  берутся из кольца (`CarRig.replaying`), вмятины пересобираются из событий в
  локальных координатах меша. Не переводить реплей на досчёт физики.

## Живая верификация (её не заменит headless)

```sh
APPDATA=<пустая папка> C:/Users/user/Desktop/Godot.exe --path . res://tests/p_live_probe.tscn --fixed-fps 60
```

Одна проверка ~2–3 минуты, GUI-окно на экране пользователя. Покрывает то, что
headless не может: аудиовывод (WASAPI), GPU-кадр, дым и следы, окраску витрины
пикселем, снимок фотомода, три пересборки дерева заезда. Харнесы с джойстиком
(`h_vibration`, `h_padflow`, `h_handbrake_devices`) в headless всегда partial:
`Input.get_connected_joypads()` в headless пуст даже с подключённым геймпадом —
судить о железе по headless-прогону нельзя.

## Текст и коммиты

- Комментарии, строки UI и сообщения коммитов — по-русски; коммит: conventional
  prefix (`fix(ui): …`, `test: …`) и тело с объяснением **почему**.
- Смешение кириллицы с латиницей и случайно попавшие CJK-иероглифы — реальный
  класс дефектов в этом репозитории. Перед коммитом прогонять
  `grep -rnIP "[\x{4E00}-\x{9FFF}\x{3040}-\x{30FF}]" --include="*.gd" --include="*.tscn" --include="*.md" --include="*.mjs" scripts tests tools README.md`
  (без `-I` скан тонет в бинарных скриншотах из `tests/out/` и даёт сотни
  ложных срабатываний) и поиск склеек `[а-я][a-zA-Z]`.
- Корневой `export_presets.cfg` — локальный и игнорируется; переносимые пресеты
  живут в `tools/export_presets.cfg`, CI собирается только из них. Не коммитить
  `artifacts/`, `tests/out/`, `tests/tmpappdata/`, `*.tpz`.
