#!/usr/bin/env node
/**
 * voice-lint.js: the shared anti-AI-tell linter (BR26092504, CLAUDE.md §34).
 *
 * Checks the mechanical rules of Slate doc WRITING-VOICE.md (rules 1 to 4 and
 * 7). Rules 5 and 6 are judgment and stay with a reviewer.
 *
 *   EM_DASH          an em dash, or `--` standing in for one
 *   EN_DASH_CLAUSE   an en dash used as a clause break (ranges such as
 *                    2020–2024 or Mon–Fri pass)
 *   CRUTCH_WORD      a stock transition or hedge from the doc's rule 3
 *   THROAT_CLEAR     an opener such as "In this module, we will"
 *   CONTRAST_SETUP   "not just X, it's Y" and its relatives
 *   SIGNOFF_FILLER   "Hope this helps!" and its relatives
 *
 * Ignored: fenced and inline code, URLs, quoted speech ("..." and “...”), and
 * the line after a `voice-lint-disable-next-line <reason>` comment. A disable
 * with no reason is itself an error.
 *
 * WHERE THE RULES LIVE. The doc is the source of truth. Its rule data is
 * mirrored in voice-rules.json beside this file, which is what a lint run
 * reads, so linting needs no network and no token. `--check-rules` fetches
 * the live doc and fails on any difference in version or crutch list, and
 * guardrails.js runs it at every session start, so the mirror cannot drift
 * quietly. `--from-slate` lints against the live doc's crutch list instead.
 *
 * Usage:
 *   voice-lint.js [options] <file...>      lint files
 *   voice-lint.js [options] -              lint stdin
 *   voice-lint.js --json <file|->          lint a JSON array of strings, or
 *                                          of {id, text}, e.g. UI copy
 *   voice-lint.js --check-rules            compare voice-rules.json to the doc
 * Options:
 *   --fix-dashes    rewrite dash findings in place (files) or to stdout
 *                   (stdin). Dashes only, never wording. Review the diff.
 *   --format json   machine-readable findings
 *   --rules <path>  a different rules file
 *   --from-slate    use the live doc's crutch list
 *   --skip <RULE,..>  rules to leave out (check-module.js skips the dash
 *                   rules, which it already counts more strictly)
 * Exit: 0 clean or warnings only, 1 any error finding (or drift, for
 * --check-rules), 2 usage or read failure, 3 doc unreachable.
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const RULES_PATH = path.join(__dirname, 'voice-rules.json');
const SLATE_URL = process.env.SLATE_URL || 'https://slate.acexoft.com';
const RULE_IDS = ['EM_DASH', 'EN_DASH_CLAUSE', 'CRUTCH_WORD', 'THROAT_CLEAR', 'CONTRAST_SETUP', 'SIGNOFF_FILLER'];
const DASH_RULES = new Set(['EM_DASH', 'EN_DASH_CLAUSE']);

/* ---------------------------------------------------------------- rules */

function escapeRe(s) { return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }

/** Compile the JSON rule data into regexes once. */
function compileRules(data) {
  const crutch = [];
  for (const c of data.crutchWords || []) {
    // An entry may narrow itself with regex `patterns` (e.g. "leverage" only
    // as a verb, since the noun is a real finance term).
    const custom = ((data.crutchPatterns || {})[c.term] || []);
    for (const p of custom) crutch.push({ term: c.term, severity: c.severity || 'error', note: c.note || null, re: new RegExp(p, 'gi') });
    if (custom.length) continue;
    const forms = [c.term, ...((data.crutchVariants || {})[c.term] || [])];
    for (const f of forms) {
      crutch.push({
        term: c.term, severity: c.severity || 'error', note: c.note || null,
        re: new RegExp(`(?<![\\w'])${escapeRe(f).replace(/ /g, '\\s+')}(?![\\w'])`, 'gi'),
      });
    }
  }
  const rx = (list) => (list || []).map((s) => new RegExp(s, 'gi'));
  return {
    docVersion: data.docVersion || null,
    crutch,
    throatClear: rx(data.throatClear),
    contrastSetup: rx(data.contrastSetup),
    signoffFiller: rx(data.signoffFiller),
    rangeWords: new Set((data.rangeWords || []).map((w) => w.toLowerCase())),
  };
}

let _defaultRules = null;
function loadRules(file) {
  if (!file && _defaultRules) return _defaultRules;
  const data = JSON.parse(fs.readFileSync(file || RULES_PATH, 'utf8'));
  const compiled = compileRules(data);
  compiled.data = data;
  if (!file) _defaultRules = compiled;
  return compiled;
}

/* -------------------------------------------------------------- masking */

/** Characters inside code, URLs or quotes become spaces in the scan copy,
 *  so no rule sees them. Curly apostrophes become straight ones. The copy
 *  keeps the line's length, so a column in it is a column in the original. */
function scanCopy(line) {
  const chars = line.replace(/[‘’]/g, "'").split('');
  const blank = (from, to) => { for (let i = from; i < to; i++) chars[i] = ' '; };
  const masks = [
    /`[^`]*`/g,                     // inline code
    /\b(?:https?:\/\/|www\.)\S+/g,  // URLs
    /"[^"\n]*"/g,                   // straight double quotes
    /“[^”\n]*”/g,    // curly double quotes
  ];
  for (const re of masks) {
    re.lastIndex = 0;
    const src = chars.join('');
    let m;
    while ((m = re.exec(src))) blank(m.index, m.index + m[0].length);
  }
  return chars.join('');
}

/* --------------------------------------------------------------- lint */

function isRangeSide(tok, rules) {
  return /^\d/.test(tok) || /\d$/.test(tok) || rules.rangeWords.has(tok.toLowerCase());
}

/** Tokens either side of position i, skipping spaces. */
function sides(s, i) {
  const left = (s.slice(0, i).match(/(\S+)\s*$/) || [])[1] || '';
  const right = (s.slice(i + 1).match(/^\s*(\S+)/) || [])[1] || '';
  const trim = (t) => t.replace(/^[^\w]+|[^\w]+$/g, '');
  return [trim(left), trim(right)];
}

/** Every dash finding on one scan-copy line: [{col, len, rule, fixable}]. */
function dashHits(scan, rules) {
  const hits = [];
  let m;
  const em = /—/g;
  while ((m = em.exec(scan))) hits.push({ col: m.index, len: 1, rule: 'EM_DASH', msg: 'em dash' });
  const dd = /(?<=\s)--(?=\s)|(?<=[A-Za-z])--(?=[A-Za-z])/g;
  while ((m = dd.exec(scan))) hits.push({ col: m.index, len: 2, rule: 'EM_DASH', msg: '"--" used as a dash' });
  const en = /–/g;
  while ((m = en.exec(scan))) {
    const [l, r] = sides(scan, m.index);
    if (l && r && isRangeSide(l, rules) && isRangeSide(r, rules)) continue;
    hits.push({ col: m.index, len: 1, rule: 'EN_DASH_CLAUSE', msg: 'en dash used as a clause break' });
  }
  return hits;
}

function lintLines(lines, rules, opts = {}) {
  const skip = new Set(opts.skip || []);
  const findings = [];
  let fence = null;
  let disabled = false;
  const push = (i, col, len, rule, severity, msg, line) => {
    if (skip.has(rule)) return;
    // Two patterns of one rule matching the same words is one finding.
    if (findings.some((f) => f.line === i + 1 && f.rule === rule && col < f._end && col + len > f.col - 1)) return;
    const from = Math.max(0, col - 25);
    const snippet = line.slice(from, Math.min(line.length, col + len + 25)).trim();
    const f = { line: i + 1, col: col + 1, rule, severity, message: msg, snippet };
    Object.defineProperty(f, '_end', { value: col + len, enumerable: false });
    findings.push(f);
  };

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const fenceMatch = line.match(/^\s*(```+|~~~+)/);
    if (fence) { if (fenceMatch && fenceMatch[1][0] === fence[0] && fenceMatch[1].length >= fence.length) fence = null; continue; }
    if (fenceMatch) { fence = fenceMatch[1]; continue; }

    const dis = line.match(/voice-lint-disable-next-line\b(.*)$/);
    if (dis) {
      const reason = dis[1].replace(/(-->|\*\/)\s*$/, '').trim();
      if (reason) disabled = true;
      else push(i, dis.index, 28, 'DISABLE_NO_REASON', 'error', 'voice-lint-disable-next-line needs a reason', line);
      continue;
    }
    if (disabled) { if (line.trim()) disabled = false; continue; }

    const scan = scanCopy(line);
    for (const h of dashHits(scan, rules)) push(i, h.col, h.len, h.rule, 'error', h.msg, line);

    // Openers are judged after list, quote and heading markers.
    const lead = (scan.match(/^\s*(?:[-*+>]\s+|\d+[.)]\s+)*/) || [''])[0].length;
    const body = scan.slice(lead);
    const throatSpans = [];
    for (const re of rules.throatClear) {
      re.lastIndex = 0;
      let m;
      while ((m = re.exec(body))) {
        throatSpans.push([lead + m.index, lead + m.index + m[0].length]);
        push(i, lead + m.index, m[0].length, 'THROAT_CLEAR', 'error', `throat-clearing opener "${m[0].trim()}"`, line);
        if (!m[0].length) re.lastIndex++;
      }
    }
    for (const c of rules.crutch) {
      c.re.lastIndex = 0;
      let m;
      while ((m = c.re.exec(scan))) {
        const inThroat = throatSpans.some(([a, b]) => m.index >= a && m.index < b);
        if (!inThroat) push(i, m.index, m[0].length, 'CRUTCH_WORD', c.severity, `stock crutch "${m[0]}"${c.note ? ` (${c.note})` : ''}`, line);
      }
    }
    for (const [rule, list, what] of [['CONTRAST_SETUP', rules.contrastSetup, 'contrast set-up'], ['SIGNOFF_FILLER', rules.signoffFiller, 'filler sign-off']]) {
      for (const re of list) {
        re.lastIndex = 0;
        let m;
        while ((m = re.exec(scan))) push(i, m.index, m[0].length, rule, 'error', `${what} "${m[0].trim()}"`, line);
      }
    }
  }
  return findings;
}

/** Lint a string. Returns findings sorted by position. */
function lint(text, opts = {}) {
  const rules = opts.rules || loadRules();
  return lintLines(String(text).split(/\r?\n/), rules, opts)
    .sort((a, b) => a.line - b.line || a.col - b.col);
}

/** Rewrite dash findings only. Clause dashes become a comma. */
function fixDashes(text, opts = {}) {
  const rules = opts.rules || loadRules();
  const eol = /\r\n/.test(text) ? '\r\n' : '\n';
  let fence = null;
  let disabled = false;
  let changed = 0;
  const out = String(text).split(/\r?\n/).map((line) => {
    const fm = line.match(/^\s*(```+|~~~+)/);
    if (fence) { if (fm && fm[1][0] === fence[0] && fm[1].length >= fence.length) fence = null; return line; }
    if (fm) { fence = fm[1]; return line; }
    if (/voice-lint-disable-next-line\b\s*\S/.test(line)) { disabled = true; return line; }
    if (disabled) { if (line.trim()) disabled = false; return line; }
    const hits = dashHits(scanCopy(line), rules).sort((a, b) => b.col - a.col);
    let s = line;
    for (const h of hits) {
      let a = h.col, b = h.col + h.len;
      while (a > 0 && s[a - 1] === ' ') a--;
      while (b < s.length && s[b] === ' ') b++;
      const before = s.slice(0, a);
      const after = s.slice(b);
      const sep = !before.trim() ? '' : (/[,;:.!?]$/.test(before) ? ' ' : (after ? ', ' : ''));
      s = before + sep + after;
      changed++;
    }
    return s;
  });
  return { text: out.join(eol), changed };
}

/* ------------------------------------------------------ doc comparison */

/** Pull the crutch list and version out of the WRITING-VOICE.md prose. */
function parseDoc(md) {
  const version = (md.match(/\*\*Version:\*\*\s*([0-9]+\.[0-9]+\.[0-9]+)/) || [])[1] || null;
  const line = md.split(/\r?\n/).find((l) => /crutches:\*\*/i.test(l));
  if (!line) return { version, crutch: null };
  const list = line.split(/crutches:\*\*/i)[1].trim().replace(/\.\s*$/, '');
  const crutch = list.split(/,\s*/).map((raw) => {
    const filler = /\(as filler\)/i.test(raw);
    const term = raw.replace(/\([^)]*\)/g, '').replace(/["“”]/g, '').replace(/[‘’]/g, "'").trim().toLowerCase();
    return { term, severity: filler ? 'warning' : 'error' };
  }).filter((c) => c.term);
  return { version, crutch };
}

function compareToDoc(data, doc) {
  const problems = [];
  if (doc.version !== data.docVersion) problems.push(`docVersion: rules file ${data.docVersion}, doc ${doc.version}`);
  if (!doc.crutch) { problems.push('doc has no "crutches:" line to compare against'); return problems; }
  const mine = new Map((data.crutchWords || []).map((c) => [c.term.toLowerCase(), c.severity || 'error']));
  const theirs = new Map(doc.crutch.map((c) => [c.term, c.severity]));
  for (const [t, sev] of theirs) {
    if (!mine.has(t)) problems.push(`doc lists "${t}", rules file does not`);
    else if (mine.get(t) !== sev) problems.push(`"${t}": rules file ${mine.get(t)}, doc implies ${sev}`);
  }
  for (const t of mine.keys()) if (!theirs.has(t)) problems.push(`rules file lists "${t}", doc does not`);
  return problems;
}

/** Slate bearer token without ever printing it (CLAUDE.md §17): the
 *  environment first, then `bws` asked for one key, output parsed in memory
 *  and never echoed, stderr discarded. Null on any failure. */
function resolveSlateToken() {
  if (process.env.SLATE_TOKEN) return process.env.SLATE_TOKEN;
  const env = { ...process.env };
  if (!env.BWS_ACCESS_TOKEN) {
    try { env.BWS_ACCESS_TOKEN = fs.readFileSync(path.join(os.homedir(), '.isconl', 'bws-access-token'), 'utf8').trim(); }
    catch { return null; }
  }
  env.BWS_API_URL = env.BWS_API_URL || 'https://api.bitwarden.eu';
  env.BWS_IDENTITY_URL = env.BWS_IDENTITY_URL || 'https://identity.bitwarden.eu';
  try {
    const raw = execFileSync('bws', ['secret', 'list'], { env, timeout: 30000, stdio: ['ignore', 'pipe', 'ignore'], encoding: 'utf8' });
    const hit = JSON.parse(raw).find((s) => s && s.key === 'SLATE_TOKEN_SCONL');
    return hit ? hit.value : null;
  } catch { return null; }
}

async function fetchDoc(key) {
  const token = resolveSlateToken();
  if (!token) return null;
  try {
    const res = await fetch(`${SLATE_URL}/api/config/${encodeURIComponent(key)}`, {
      headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(15000),
    });
    if (!res.ok) return null;
    const body = await res.text();
    try { const j = JSON.parse(body); return typeof j === 'string' ? j : (j.content || j.body || j.text || body); }
    catch { return body; }
  } catch { return null; }
}

/* ------------------------------------------------------------------ CLI */

const PROSE_EXT = /\.(md|mdoc|markdown|txt)$/i;
const SKIP_DIRS = new Set(['node_modules', '.git', 'target', 'dist', 'build', 'vendor', '_superseded']);

/** Files as given; a directory expands to the prose files under it. */
function expandPaths(list) {
  const out = [];
  const walk = (dir) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, e.name);
      if (e.isDirectory()) { if (!SKIP_DIRS.has(e.name) && !e.name.startsWith('.')) walk(full); }
      else if (PROSE_EXT.test(e.name)) out.push(full);
    }
  };
  for (const p of list) {
    if (fs.statSync(p).isDirectory()) walk(p);
    else out.push(p);
  }
  return out.sort();
}

function format(source, f) {
  return `${source}:${f.line}:${f.col}: ${f.rule} (${f.severity}) ${f.message}  |  ${f.snippet}`;
}

async function main(argv) {
  const args = { files: [], skip: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--fix-dashes') args.fix = true;
    else if (a === '--format') args.format = argv[++i];
    else if (a === '--rules') args.rules = argv[++i];
    else if (a === '--json') args.json = argv[++i];
    else if (a === '--from-slate') args.fromSlate = true;
    else if (a === '--check-rules') args.checkRules = true;
    else if (a === '--skip') args.skip = String(argv[++i] || '').split(',').map((s) => s.trim()).filter(Boolean);
    else if (a === '-h' || a === '--help') { console.log(fs.readFileSync(__filename, 'utf8').split('*/')[0]); return 0; }
    else args.files.push(a);
  }

  let data;
  try { data = JSON.parse(fs.readFileSync(args.rules || RULES_PATH, 'utf8')); }
  catch (e) { console.error(`voice-lint: cannot read rules: ${e.message}`); return 2; }

  if (args.checkRules || args.fromSlate) {
    const md = await fetchDoc(data.docKey || 'WRITING-VOICE.md');
    if (!md) {
      console.error(`voice-lint: could not reach Slate doc ${data.docKey || 'WRITING-VOICE.md'}${args.fromSlate ? '; linting with voice-rules.json' : ''}`);
      if (args.checkRules) return 3;
    } else {
      const doc = parseDoc(md);
      if (args.checkRules) {
        const problems = compareToDoc(data, doc);
        if (!problems.length) { console.log(`voice-lint: voice-rules.json matches ${data.docKey} v${doc.version}`); return 0; }
        console.log(`voice-lint: voice-rules.json has drifted from ${data.docKey}:\n  ${problems.join('\n  ')}`);
        return 1;
      }
      if (doc.crutch) data = { ...data, crutchWords: doc.crutch };
    }
  }

  const rules = compileRules(data);
  const opts = { rules, skip: args.skip };
  const inputs = [];
  const readStdin = () => fs.readFileSync(0, 'utf8');
  try {
    if (args.json) {
      const arr = JSON.parse(args.json === '-' ? readStdin() : fs.readFileSync(args.json, 'utf8'));
      if (!Array.isArray(arr)) throw new Error('--json input must be an array');
      const base = args.json === '-' ? 'stdin' : args.json;
      arr.forEach((v, idx) => {
        const id = v && typeof v === 'object' ? (v.id ?? idx) : idx;
        inputs.push({ source: `${base}[${id}]`, text: typeof v === 'string' ? v : String((v && v.text) || '') });
      });
    } else if (!args.files.length || args.files.includes('-')) {
      inputs.push({ source: 'stdin', text: readStdin(), stdin: true });
    } else {
      for (const f of expandPaths(args.files)) inputs.push({ source: f, text: fs.readFileSync(f, 'utf8'), file: f });
    }
  } catch (e) { console.error(`voice-lint: ${e.message}`); return 2; }

  if (args.fix) {
    let total = 0;
    for (const inp of inputs) {
      const r = fixDashes(inp.text, opts);
      total += r.changed;
      if (inp.stdin) process.stdout.write(r.text);
      else if (inp.file && r.changed) fs.writeFileSync(inp.file, r.text);
    }
    console.error(`voice-lint: rewrote ${total} dash(es); review the diff, wording is untouched`);
  }

  const all = [];
  for (const inp of inputs) {
    const text = args.fix && inp.file ? fs.readFileSync(inp.file, 'utf8') : (args.fix ? fixDashes(inp.text, opts).text : inp.text);
    for (const f of lint(text, opts)) all.push({ source: inp.source, ...f });
  }
  const errors = all.filter((f) => f.severity === 'error').length;
  const warnings = all.length - errors;
  if (args.format === 'json') console.log(JSON.stringify(all, null, 2));
  else if (!(args.fix && inputs.some((i) => i.stdin))) {
    for (const f of all) console.log(format(f.source, f));
    console.log(`voice-lint: ${errors} error(s), ${warnings} warning(s) in ${inputs.length} input(s)`);
  }
  return errors ? 1 : 0;
}

if (require.main === module) {
  main(process.argv.slice(2)).then((code) => { process.exitCode = code; }, (e) => { console.error(`voice-lint: ${e.message}`); process.exitCode = 2; });
}

module.exports = { lint, fixDashes, loadRules, compileRules, parseDoc, compareToDoc, RULE_IDS, DASH_RULES };
