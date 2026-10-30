# Car Crash Simulator

3D-краш-песочница в духе BeamNG.drive на Godot 4.7: мягкая verlet-деформация кузова,
3 машины, 3 карты, слоу-мо, камера свободной орбиты.

## Запуск

1. Открой `C:\Users\makscoder\Desktop\Godot.exe` (Godot 4.7.2).
2. Импорт проекта: выбери папку `carcrashsimulator` (файл `project.godot`).
3. Нажми **F5** — игра запустится с меню.

## Управление

| Действие | Клавиатура | Геймпад |
|---|---|---|
| Газ / тормоз | W / S | RT / LT |
| Руль | A/D, ←/→ | левый стик |
| Ручник (дрифт) | Space | A |
| Слоу-мо (удержание) | Shift | B |
| Камера (погоня → капот → орбита) | C | X |
| Рестарт | R | Y |
| Пауза | Esc | Start |

## Как устроена деформация

Рама — жёсткий `RigidBody3D` с аркадным контроллером. Кузов — verlet-клетка
(~320 точек, ~1400 пружин), целые зоны которой следуют за рамой (FOLLOW), а повреждённые
симулируются физикой (DYNAMIC): пружины пластически текут (вмятина остаётся) и рвутся
при длительной перегрузке. Столкновение клетки с миром — свип-лучи + аналитический
AABB-барьер (`ObstacleField`). Удар считается по раме: `body_entered` + скоростной
клармп носовым лучом.

## Структура

```
scripts/core/     car_rig, soft_shell, shell_builder, damage_model, effects_director,
                  camera_rig, game_manager, obstacle_field, vehicle_params/db
scripts/maps/     map_db (арена / городок / трасса, процедурно)
scripts/ui/       main_menu, hud
scripts/autoload/ GameContext, TimeScale, InputRouter
tests/            смоук-тесты и интеграционные харнесы
docs/superpowers/ спека и план внедрения
```

## Тесты

```
"C:\Users\makscoder\Desktop\Godot.exe" --headless --path . --import
# data-тесты:
"C:\Users\makscoder\Desktop\Godot.exe" --headless --path . --script res://tests/t4_shell.gd
# интеграционные харнесы (с фикс. шагом):
"C:\Users\makscoder\Desktop\Godot.exe" --headless --path . --fixed-fps 60 --quit-after 1400 res://tests/h_t7_crash.tscn
```

Все 14 тестов проходят: стабильность клетки, удар/разрыв/пластичность, вождение,
краш-сценарий (≥12 порванных пружин, остановка, сон клетки, бюджет <8 мс/кадр),
9 комбинаций карта×машина.

## Вне v1

Звук, AI-трафик, экспорт .exe, сеть, манекены.
