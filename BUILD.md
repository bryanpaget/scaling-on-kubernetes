# Build Architecture and Fork Guide

This document explains how the presentation is built and how to fork this repo into
a new topic. The current deck is "Scaling on Kubernetes" (VPA, KEDA, and Karpenter on
the Aurora Platform); the same build machinery works for any Marp deck. Read this
before changing the build or re-theming.

---

## 1. How the build works

The decks are authored as Marp Markdown and compiled to self-contained HTML. There
are two source files (English and French), a shared per-language header, and a Node
build script that does the actual rendering.

```
config/header-en.md  +  content/slides-en.md   ->  temp/slides-en-combined.md  ->  docs/en.html
config/header-fr.md  +  content/slides-fr.md   ->  temp/slides-fr-combined.md  ->  docs/fr.html
config/landing.html                             ->  docs/index.html
img/*                                           ->  docs/img/*
```

The orchestration lives in the `Makefile`. The important target is:

```bash
make html
```

Which runs, in order:
1. `combine-en` / `combine-fr` - concatenate the header file and the slides file into
   `temp/slides-*-combined.md` (a plain `cat`).
2. `npx marp --html ...` (Marp CLI) - render each combined Markdown file into a full,
   clickable "bespoke" presentation (slide-by-slide, arrow-key navigation).
3. `node postprocess.mjs` - inject the aurora theme CSS and tag large code blocks.
4. Copy `config/landing.html` to `docs/index.html` and copy `img/` into `docs/img/`.

### Why the Marp CLI + a post-processor

This is the single most important thing to understand, and it cost a lot of time to
work out:

- The HTML build uses the **Marp CLI** (`npx marp`), NOT the Marp Core library directly.
- The CLI output includes the **bespoke player**: the JavaScript and CSS that make the
  deck a clickable, one-slide-at-a-time presentation. If you render with the Marp Core
  library's `marp.render()` instead, you only get raw slide SVGs with no player, and the
  page becomes a long vertical scroll of every slide. That is the regression to avoid.
- The custom aurora theme and code-size tweaks are applied **after** the CLI runs, by
  `postprocess.mjs`, which injects a `<style>` block before `</head>` and tags long
  code blocks. This keeps the clickable player intact.

The Marp CLI **hangs on exit** in this WSL environment (Chromium/puppeteer cleanup).
The HTML file is fully written before the hang, so the `html` target wraps each `npx
marp` call in `timeout` and ignores its exit status (the `-` prefix in the Makefile).
The build still succeeds. If a build appears to pause at the end, that is the hang, not
a failure.

### Dependencies

Declared in `package.json`:

- `@marp-team/marp-cli` (devDependency) - the only dependency. It bundles its own
  Marp Core, so nothing else is needed.

Do **NOT** add `@marp-team/marp-core` or `shiki` as project dependencies. They shadow
the CLI's bundled core and break the CLI with `ERR_REQUIRE_ESM` (shiki is ESM) or
`Cannot find module 'shiki/core'`. If the CLI starts failing with those errors, check
that these packages are not in `package.json` / `node_modules`.

Install with:

```bash
npm install
```

### A note on Mermaid

Earlier versions of this deck tried to render Mermaid diagrams. Server-side Mermaid
rendering in `marp-core` was unreliable in this environment (a `require()` of an ESM
internal throws). The component diagram on the "How VPA Works" slide is therefore built
as **plain HTML/CSS** (the `.flow` / `.flow-box` / `.plate` classes), not Mermaid. This
renders predictably inside Marp's fixed-size slides with no external library and no
network dependency. Prefer this approach for any new diagrams.

### PDF build (secondary)

`make pdf` uses the Marp CLI and Chromium. It is not the primary path and may need
attention after dependency changes. The HTML site (`make html`) is the supported,
reliable output and is what GitHub Pages serves.

---

## 2. Where the theme lives

All custom styling is centralized in **`postprocess.mjs`**:

- `const AURORA = 'linear-gradient(...)'` - the single "aurora borealis" gradient
  definition. Change this one line to re-palette the whole deck.
- `const EXTRA_CSS = ...` - all theme rules, layered on top of Marp's generated CSS:
  - `section h2` - aurora gradient underline on slide titles
  - `section h3` - aurora-blue sub-headings
  - `section footer` - aurora-blue footer
  - `section blockquote` - gradient left bar callout
  - `section table` - gradient header row, flat square cells, zebra striping
  - `section a` - aurora-blue links
  - `.flow` / `.flow-box` / `.plate` / `.flow-arrow` - the component diagram on the
    "How VPA Works" slide

The look is intentionally flat and square (no rounded corners, no shadows).

Per-slide font sizes live in the `style:` block of `config/header-en.md` and
`config/header-fr.md`.

---

## 3. `docs/` is generated - never hand-edit

Everything in `docs/` (`en.html`, `fr.html`, `index.html`, `img/`) is build output.
Never edit those files by hand. Always edit the sources and run `make html`. GitHub
Pages serves the committed `docs/` folder, so after editing slides you must rebuild
and commit the regenerated `docs/`.

---

## 4. Forking into a new topic (e.g., Karpenter)

To turn this into a presentation about a different topic, edit the following. The
build system, Makefile, and `build-html.mjs` do **not** need to change - only content,
headers, the landing page, and the README.

**Content (the slides themselves):**
- `content/slides-en.md` - rewrite the English slides for the new topic.
- `content/slides-fr.md` - rewrite the French slides. Keep slide count and structure
  in sync with the English file.

**Headers (titles, frontmatter, footer):**
- `config/header-en.md` - update the `header:`, `footer:`, the `# H1` title, the
  `## H2` subtitle, and the author/date lines.
- `config/header-fr.md` - same, in French.

**Landing page:**
- `config/landing.html` - update the hero title, subtitle, "About" bullets, the
  documentation links, and the footer for the new topic.

**README:**
- `README.md` - update the title, executive summary, table of contents, and all the
  topic content. (The English and French halves are both inlined here.)

**Images (optional):**
- `img/aurora.png` - the hero/brand image used on title slides and the landing page.
  Replace if the new topic needs different branding; otherwise leave it.

**Theme (optional):**
- Leave `build-html.mjs` alone unless you want a different color palette. If you do,
  change the `AURORA` constant.

**What to leave untouched:**
- `Makefile`, `postprocess.mjs`, `.github/workflows/`, `package.json` - the build
  machinery is topic-agnostic.

### Fork checklist

1. Copy the repo, update `package.json` `name`/`description`.
2. `npm install`.
3. Rewrite `content/slides-en.md` and `content/slides-fr.md` for the new topic.
4. Update `config/header-en.md` and `config/header-fr.md` (titles, header, footer).
5. Update `config/landing.html` (hero + links).
6. Update `README.md`.
7. Replace `img/aurora.png` if needed.
8. `make html` and open `docs/en.html` / `docs/fr.html` to verify.
9. Commit the regenerated `docs/`.

---

## 5. Quick reference

```bash
make html          # Build the HTML site into docs/ (primary, reliable path)
make preview-en    # Live preview English on localhost (Marp CLI)
make preview-fr    # Live preview French on localhost (Marp CLI)
make pdf           # Build PDFs (secondary, needs Marp CLI + Chromium)
make clean         # Remove temp/ and generated PDFs
```
