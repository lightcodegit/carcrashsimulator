# Car Crash Simulator — сайт

Лендинг игры для GitHub Pages. Статика без сборки: `index.html` + `style.css` + ассеты.

## Что где

- `index.html` — одна страница: герой, фичи, скриншоты, загрузка, требования.
- `style.css` — тёмная тема с янтарным акцентом, в тон интерфейсу игры.
- `assets/` — три скриншота из игры (копии из `docs/images/` репозитория) и favicon.

## Обновление скриншотов

Скриншоты — копии из репозитория игры. После нового красивого кадра:

```sh
cp ../carcrashsimulator/docs/images/*.jpg assets/
```

## Публикация

Сайт деплоится веткой `gh-pages` репозитория игры
(страница: https://lightcodegit.github.io/carcrashsimulator/).
Обновить выложенную версию:

```sh
git clone --branch gh-pages https://github.com/lightcodegit/carcrashsimulator gh-pages-work
cp -r index.html style.css assets gh-pages-work/
cd gh-pages-work
git add -A && git commit -m "site: update" && git push
```

Включение Pages (один раз): Settings → Pages → Source: Deploy from a branch →
`gh-pages` / root. Включается и через API (`POST /repos/.../pages`).
