import { Marp } from '@marp-team/marp-core'
import fs from 'fs'

// Extra styles layered on top of Marp's generated CSS.
// `.flow` is a horizontal three-box component diagram used on the
// "How VPA Works" slide (plain HTML/CSS so it renders predictably
// inside Marp's fixed-size slides, no external libraries, no clipping).
// Shared "aurora borealis" gradient (teal -> blue -> purple -> mint).
const AURORA = 'linear-gradient(135deg,#1de9b6 0%,#2979ff 35%,#7c4dff 70%,#64ffda 100%)'

const EXTRA_CSS = `
/* ---- Aurora theme applied across slides ---- */

/* H2 slide titles: aurora gradient underline accent */
section h2 {
  padding-bottom:8px; margin-bottom:16px;
  border-bottom:4px solid transparent;
  border-image:${AURORA} 1;
}

/* H3 sub-headings get a soft aurora-blue tint */
section h3 { color:#2554c7; }

/* Footer tinted aurora blue */
section footer { color:#2979ff; font-weight:600; }

/* Blockquotes: flat callout with aurora gradient left bar */
section blockquote {
  border-left:6px solid transparent; border-image:${AURORA} 1;
  background:#f3f8ff; padding:12px 18px; font-style:italic;
}

/* Tables: aurora gradient header row, flat square cells */
section table { border-collapse:collapse; }
section table th {
  background:${AURORA}; color:#fff; font-weight:600;
  border:1px solid #cbd8f0; text-shadow:0 1px 2px rgba(0,0,0,0.25);
}
section table td { border:1px solid #d4e4e0; }
section table tr:nth-child(even) td { background:#f3f8ff; }

/* Links in the aurora blue */
section a { color:#2979ff; }

/* ---- "How VPA Works" component flow (stack of plates) ---- */
.flow { display:flex; align-items:stretch; justify-content:center; gap:16px; margin-top:18px; }
.flow-box {
  flex:1 1 0; background:#fff;
  border:3px solid transparent; border-image:${AURORA} 1;
}
.plate {
  padding:14px 16px; font-size:19px; line-height:1.3; text-align:center;
  border-bottom:1px solid #d4e4e0;
}
.plate:last-child { border-bottom:none; }
.plate-head {
  background:${AURORA};
  color:#fff; font-size:24px; font-weight:bold; border-bottom:none;
  text-shadow:0 1px 2px rgba(0,0,0,0.35);
}
.flow-arrow { display:flex; align-items:center; font-size:48px; color:#2979ff; font-weight:bold; }
`

const buildSlides = (inputFile, outputFile, lang, title) => {
  const marp = new Marp({ html: true })
  const markdown = fs.readFileSync(inputFile, 'utf8')
  const { html, css } = marp.render(markdown)

  const doc = `<!DOCTYPE html>
<html lang="${lang}">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${title}</title>
<style>${css}</style>
<style>${EXTRA_CSS}</style>
</head>
<body>
${html}
</body>
</html>
`
  fs.writeFileSync(outputFile, doc)
  console.log(`Wrote ${outputFile} (${doc.length} bytes)`)
}

buildSlides('temp/slides-en-combined.md', 'docs/en.html', 'en', 'Vertical Pod Autoscaler (VPA) - Aurora Platform')
buildSlides('temp/slides-fr-combined.md', 'docs/fr.html', 'fr', 'Vertical Pod Autoscaler (VPA) - Plateforme Aurora')

console.log('Done.')
