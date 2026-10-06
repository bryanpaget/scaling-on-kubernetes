import fs from 'fs'

// Post-process Marp CLI HTML output: tag large code blocks with a smaller-font class.
// No theme injection - use Marp's built-in themes as-is.

const tagCodeBlocks = (html) =>
  html.replace(/(<pre\b)([^>]*?)(>\s*<code[^>]*>)([\s\S]*?)(<\/code>)/g,
    (m, open, attrs, mid, code, close) => {
      if (/class=/.test(attrs)) return m
      const lines = code.replace(/\n$/, '').split('\n').length
      const cls = lines >= 18 ? ' class="code-xl"' : lines >= 11 ? ' class="code-lg"' : ''
      return `${open}${attrs}${cls}${mid}${code}${close}`
    })

const processFile = (file) => {
  let html = fs.readFileSync(file, 'utf8')
  html = tagCodeBlocks(html)
  fs.writeFileSync(file, html)
  console.log(`Post-processed ${file}`)
}

const files = process.argv.slice(2)
if (files.length === 0) {
  console.error('Usage: node postprocess.mjs <file.html> [...]')
  process.exit(1)
}
for (const f of files) processFile(f)
