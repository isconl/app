'use strict';
/**
 * BI26092602: user-visible strings from the Flutter app (the .dart files under `lib/`) for voice-lint.
 *
 * A net, not a parser. It reads the string given to the widgets and named arguments a person sees: Text('...'),
 * SelectableText, and `label:`, `title:`, `subtitle:`, `tooltip:`, `hintText:`, `helperText:`, `labelText:`,
 * `message:`, `semanticsLabel:` arguments. Interpolations ($name, ${expr}) are blanked, adjacent literals are not
 * joined (each is checked alone), imports, part directives, keys and route names are never matched because they are
 * not given through those names. A string it misses is a missed warning, never a false failure.
 */
const fs = require('fs');
const path = require('path');

const NAMED = ['label', 'title', 'subtitle', 'tooltip', 'hintText', 'helperText', 'labelText', 'message', 'semanticsLabel', 'text'];
const STR = String.raw`(?:'((?:\\.|[^'\\\n])*)'|"((?:\\.|[^"\\\n])*)")`;

const looksLikeCopy = (s) => {
  const t = s.replace(/\s+/g, ' ').trim();
  if (t.length < 4 || !/[A-Za-z]{3,}/.test(t)) return false;
  if (/^[\w./-]+\.(dart|png|svg|json|ttf|webp)$/i.test(t)) return false;
  if (/^\/|^https?:|^package:|[{};]|=>/.test(t)) return false;
  return true;
};

const lineOf = (text, i) => { let n = 1; for (let k = 0; k < i; k++) if (text.charCodeAt(k) === 10) n++; return n; };

function walk(dir, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.dart') && !/\.(g|freezed)\.dart$/.test(e.name)) out.push(p);
  }
  return out;
}

function fromDart(file, text, out) {
  const patterns = [
    new RegExp(String.raw`\b(?:Text|SelectableText)\(\s*${STR}`, 'g'),
    new RegExp(String.raw`\b(?:${NAMED.join('|')})\s*:\s*${STR}`, 'g'),
  ];
  for (const re of patterns) {
    let m;
    while ((m = re.exec(text))) {
      const raw = (m[1] !== undefined ? m[1] : m[2]) || '';
      const clean = raw.replace(/\\n/g, ' ').replace(/\\(['"$\\])/g, '$1').replace(/\$\{[^}]*\}/g, ' ').replace(/\$[A-Za-z_]\w*/g, ' ').replace(/\s+/g, ' ').trim();
      if (looksLikeCopy(clean)) out.push({ id: `${file}:${lineOf(text, m.index)}`, text: clean });
    }
  }
}

/** @returns {{id: string, text: string}[]} */
function extract(root) {
  const out = [];
  for (const f of walk(path.join(root, 'lib')).sort()) fromDart(path.relative(root, f).replace(/\\/g, '/'), fs.readFileSync(f, 'utf8'), out);
  return out;
}

module.exports = { extract, looksLikeCopy };