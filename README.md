# Car Crash Simulator — site

The landing page for GitHub Pages. Plain static files, no build step:
`index.html` + `style.css` + assets.

## Layout

- `index.html` — a single page: hero, features, screenshots, download, requirements.
- `style.css` — a dark theme with the amber gauge accent, matching the game UI.
- `assets/` — screenshots (copies from the game repository's `docs/images/`),
  the game emblem (`logo.svg`, from `assets/ui/logo_emblem.svg`) and the favicon.

## Updating screenshots

Screenshots are copies from the game repository. After a fresh good frame:

```sh
cp ../carcrashsimulator/docs/images/*.jpg assets/
```

## Publishing

The site deploys from the `gh-pages` branch of the game repository
(the page: https://lightcodegit.github.io/carcrashsimulator/).
To update the published copy:

```sh
git clone --branch gh-pages https://github.com/lightcodegit/carcrashsimulator gh-pages-work
cp -r index.html style.css assets gh-pages-work/
cd gh-pages-work
git add -A && git commit -m "site: update" && git push
```

Enabling Pages (once): Settings → Pages → Source: Deploy from a branch →
`gh-pages` / root. It can also be enabled through the API
(`POST /repos/.../pages`).
