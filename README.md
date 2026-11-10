# Car Crash Simulator — site

The landing page for GitHub Pages. Plain static files, no build step:
`index.html` + `dossier.css` + `dossier-i18n.js` + `dossier.js` + assets.

The visual language is a "crash dossier": warm paper, ink, one signal-orange
accent, hazard stripes and mono labels styled like a crash-test report — the
benchmark section flips to the dark instrument panel.

## Layout

- `index.html` — a single page: hero with a spec table, ticker tape,
  numbered crash log, the interactive frame-cost instrument (dark),
  an evidence board of screenshots, open-source stats, the default
  controls table, download and requirements.
- `dossier.css` — the design system: paper theme, Archivo (display) and
  JetBrains Mono (labels), prefers-reduced-motion respected.
- `dossier-i18n.js` — the full EN/RU dictionary; the language is switchable on the
  fly and stored in `localStorage` (`ccs-lang`). Every string on the page
  is checked in here.
- `dossier.js` — reveal-on-scroll, the sticky header state, the ticker tape
  and the benchmark instrument: the slider drives the frame cost, the
  render scale is derived from it (the `p_perf` measurements, live
  rendering at 1600×900 on Intel HD 630).
- `assets/` — screenshots (copies from the game repository's
  `docs/images/`), the game emblem (`logo.svg`, from
  `assets/ui/logo_emblem.svg`) and the favicon.

## Updating screenshots and numbers

Screenshots are copies from the game repository:

```sh
cp ../carcrashsimulator/docs/images/*.jpg assets/
```

The version lives in `index.html` (hero button, download heading) and in the
`dossier-i18n.js` dictionary — sync it with the `v*` tag in the game
repository. The download plates always point at the Releases page, not a
pinned version. Benchmark numbers come from the Performance section of the
game README (`PRESETS` in `dossier.js`).

## Preview

Open `index.html` directly, or serve the folder (fonts are the only
external request):

```sh
npx serve .
```

## Publishing

The site deploys from the `gh-pages` branch of the game repository
(the page: https://lightcodegit.github.io/carcrashsimulator/).
To update the published copy:

```sh
git clone --branch gh-pages https://github.com/lightcodegit/carcrashsimulator gh-pages-work
cp -r index.html dossier.css dossier-i18n.js dossier.js assets gh-pages-work/
cd gh-pages-work
git add -A && git commit -m "site: redesign" && git push
```

Enabling Pages (once): Settings → Pages → Source: Deploy from a branch →
`gh-pages` / root. It can also be enabled through the API
(`POST /repos/.../pages`).
