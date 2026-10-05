# Presentation Build - Project Steering

This repository is a bilingual (English/French) Marp presentation: "Scaling on
Kubernetes" - a platform-team guide covering VPA, KEDA, and Karpenter and how they
interact. (The repo is still named `vpa-presentation` for now; it may be renamed
later.) These are the rules and facts a Kiro session needs before touching the build
or re-theming the deck. Full detail is in #[[file:BUILD.md]].

## Build facts

- The HTML site is built with `make html`. It runs the **Marp CLI** (`npx marp --html`)
  to produce the clickable "bespoke" presentation (slide-by-slide, arrow-key nav), then
  runs `node postprocess.mjs` to inject the aurora theme and code-size classes.
- The Marp CLI is what makes the output a real clickable presentation. Do NOT render
  with the Marp Core library directly (`marp.render()`) - it omits the bespoke player
  JS and the result becomes a long vertical scroll of all slides.
- Keep the project deps minimal: only `@marp-team/marp-cli` (devDependency). Do NOT add
  `@marp-team/marp-core` or `shiki` as project deps - they shadow the CLI's own bundled
  core and break the CLI with `ERR_REQUIRE_ESM` (shiki ESM) / `shiki/core` errors.
- The Marp CLI hangs on exit in this WSL environment (Chromium/puppeteer cleanup), so
  the `html` target wraps each `npx marp` call in `timeout` and ignores its exit code
  (`-` prefix). The HTML file is written before the hang, so the build still succeeds.
- `make pdf` is a secondary path (Marp CLI + Chromium) and may be fragile. `make html`
  is the supported, reliable output.

## Theme

- All custom CSS lives in `postprocess.mjs` in `EXTRA_CSS`, built on the single `AURORA`
  gradient constant. Re-palette by changing `AURORA` only. The post-processor injects
  this CSS before `</head>` and tags long code blocks `.code-lg` / `.code-xl`.
- The look is flat and square: no rounded corners, no shadows.
- Diagrams are plain HTML/CSS (`.flow` / `.flow-box` / `.plate`), NOT Mermaid.
  Server-side Mermaid is unreliable here - do not reintroduce it. Build new diagrams
  as HTML/CSS.

## Content layout

- English slides: `content/slides-en.md`; French slides: `content/slides-fr.md`.
- Per-language title/frontmatter/footer: `config/header-en.md`, `config/header-fr.md`.
- Landing page: `config/landing.html` (copied to `docs/index.html`).
- Keep the English and French decks in sync (same slide count and structure).
- Deck structure: intro (scaling-axes map + layering) -> Part 1 VPA -> Part 2 KEDA ->
  Part 3 Karpenter -> Part 4 interactions/anti-patterns -> conclusion/references.
- Content accuracy is sourced from local Aurora material, not guessed: the Karpenter
  proposal and the VPA/KEDA usage guides in the `docs-main` repo (on branches
  `proposal-karpenter` / `vpa-usage` / `keda-usage`), plus the `aurora-platform-charts`
  repo (branches `add-vpa`, `add-keda`, `define-keda-patterns`). Pull current
  CRD/API syntax from upstream docs before changing YAML; do not use stale syntax.

## Hard rules

- `docs/` is generated output. NEVER hand-edit files in `docs/`. Edit sources and run
  `make html`, then commit the regenerated `docs/`.
- When forking this repo into a new topic, change content/headers/landing/README only.
  Leave `Makefile`, `postprocess.mjs`, `package.json`, and `.github/workflows/` alone
  unless changing the palette. Follow the fork checklist in #[[file:BUILD.md]].
- No em-dashes or special Unicode punctuation in slide or doc content; use regular
  hyphens or colons.
