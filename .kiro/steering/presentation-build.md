# Presentation Build - Project Steering

This repository is a bilingual (English/French) Marp presentation. These are the
rules and facts a Kiro session needs before touching the build or re-theming the deck.
Full detail is in #[[file:BUILD.md]].

## Build facts

- The HTML site is built with `make html`, which runs `node build-html.mjs`.
- `build-html.mjs` uses **Marp Core (the library)**, not the Marp CLI. It calls
  `marp.render()` and assembles a full HTML document, injecting the returned `css`
  into a `<style>` tag. This is required - skipping it leaves slides unstyled.
- Do NOT replace `make html` with `npx marp --html`. The CLI path produces partial,
  unstyled documents here and ignores the custom theme.
- `shiki` must stay installed (Marp Core needs it for code highlighting; missing it
  causes `Cannot find module 'shiki/core'`).
- `make pdf` is a secondary path (Marp CLI + Chromium) and may be fragile. `make html`
  is the supported, reliable output.

## Theme

- All custom CSS lives in `build-html.mjs` in `EXTRA_CSS`, built on the single `AURORA`
  gradient constant. Re-palette by changing `AURORA` only.
- The look is flat and square: no rounded corners, no shadows.
- Diagrams are plain HTML/CSS (`.flow` / `.flow-box` / `.plate`), NOT Mermaid.
  Server-side Mermaid is unreliable here - do not reintroduce it. Build new diagrams
  as HTML/CSS.

## Content layout

- English slides: `content/slides-en.md`; French slides: `content/slides-fr.md`.
- Per-language title/frontmatter/footer: `config/header-en.md`, `config/header-fr.md`.
- Landing page: `config/landing.html` (copied to `docs/index.html`).
- Keep the English and French decks in sync (same slide count and structure).

## Hard rules

- `docs/` is generated output. NEVER hand-edit files in `docs/`. Edit sources and run
  `make html`, then commit the regenerated `docs/`.
- When forking this repo into a new topic, change content/headers/landing/README only.
  Leave `Makefile`, `build-html.mjs`, `package.json`, and `.github/workflows/` alone
  unless changing the palette. Follow the fork checklist in #[[file:BUILD.md]].
- No em-dashes or special Unicode punctuation in slide or doc content; use regular
  hyphens or colons.
