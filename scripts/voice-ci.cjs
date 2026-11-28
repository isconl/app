#!/usr/bin/env node
/**
 * voice-ci.js: the anti-AI-tell check for CI, in every repo that has user-facing text (BR26100102 items 1, 2 and 4,
 * CLAUDE.md section 34). It fails a push or pull request only on findings that are NEW against the repo's baseline,
 * so the findings already there are fixed through the comb's rows without blocking every push, and the baseline can
 * only shrink.
 *
 *   node scripts/voice-ci.js check    [--root .] [--base <git ref>]   lint; exit 1 on a finding the baseline lacks
 *   node scripts/voice-ci.js baseline [--root .]                      write .voice-lint-baseline.json from a full scan
 *   node scripts/voice-ci.js shrink   [--root .] --base <git ref>     exit 1 if the baseline grew against <ref>
 *
 * It reads `.voice-lint.json` at the repo root: { "include": ["README.md", "web/**\/*.js"], "exclude": ["**\/node_modules/**"],
 * "minLiteral": 12 }. Globs support `**` and `*`. With --base only the files changed since that ref are linted.
 *
 * What is linted, by file type:
 *  - .md .mdx .txt: the whole text.
 *  - .html .htm: the text between tags (script and style blocks and the tags themselves are blanked, lines kept).
 *  - .js .mjs .cjs .jsx .ts .tsx .dart: string literals that read as UI copy (at least `minLiteral` characters and a
 *    space), one per line. A `voice-lint-disable-next-line <reason>` comment on the line before a literal is honoured,
 *    and a disable with no reason is itself an error, as in voice-lint.js.
 * Only error-level findings count. A finding is its file, its rule and its line's text, so moving a line is not new.
 *
 * Exit codes: 0 ok, 1 new findings or a grown baseline, 2 usage.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const cp = require('child_process');
const { lint } = require('./voice-lint.cjs');

const BASELINE = '.voice-lint-baseline.json';
const CONFIG = '.voice-lint.json';
const DEFAULTS = { include: ['**/*.md'], exclude: ['**/node_modules/**', '**/.git/**', '**/target/**', '**/dist/**', '**/build/**', '**/_superseded/**'], minLiteral: 12 };
const MARK = 'voice-lint-disable-next-line';

function globToRe(g) {
  let re = '';
  for (let i = 0; i < g.length; i++) {
    const c = g[i];
    if (c === '*' && g[i + 1] === '*') { re += '.*'; i++; if (g[i + 1] === '/') i++; }
    else if (c === '*') re += '[^/]*';
    else if (c === '?') re += '[^/]';
    else re += c.replace(/[.+^${}()|[\]\\]/g, '\\$&');
  }
  return new RegExp(`^${re}$`);
}
const matchAny = (res, p) => res.some(r => r.test(p));

function readConfig(root) {
  let c = {};
  try { c = JSON.parse(fs.readFileSync(path.join(root, CONFIG), 'utf8').replace(/^﻿/, '')); } catch { /* defaults */ }
  return { include: c.include || DEFAULTS.include, exclude: [...DEFAULTS.exclude, ...(c.exclude || [])], minLiteral: c.minLiteral || DEFAULTS.minLiteral };
}

function listFiles(root, cfg, only) {
  const inc = cfg.include.map(globToRe);
  const exc = cfg.exclude.map(globToRe);
  const out = [];
  const walk = (dir) => {
    for (const e of fs.readdirSync(path.join(root, dir), { withFileTypes: true })) {
      const rel = dir ? `${dir}/${e.name}` : e.name;
      if (matchAny(exc, rel) || matchAny(exc, `${rel}/`)) continue;
      if (e.isDirectory()) walk(rel);
      else if (matchAny(inc, rel) && (!only || only.has(rel))) out.push(rel);
    }
  };
  walk('');
  return out.sort();
}

/** Blank everything that is not visible text, keeping every line break so line numbers hold. */
function htmlText(src) {
  const blank = (m) => m.replace(/[^\n]/g, ' ');
  return src.replace(/<script[\s\S]*?<\/script>/gi, blank).replace(/<style[\s\S]*?<\/style>/gi, blank).replace(/<!--[\s\S]*?-->/g, blank).replace(/<[^>]*>/g, blank);
}

/** String literals of a code file as { line, text }, comments skipped. Template literals give their text chunks. */
function literals(src) {
  const out = [];
  let i = 0, line = 1;
  const n = src.length;
  const flush = (buf, startLine) => { if (buf) out.push({ line: startLine, text: buf }); };
  while (i < n) {
    const c = src[i], d = src[i + 1];
    if (c === '\n') { line++; i++; continue; }
    if (c === '/' && d === '/') { while (i < n && src[i] !== '\n') i++; continue; }
    if (c === '/' && d === '*') { i += 2; while (i < n && !(src[i] === '*' && src[i + 1] === '/')) { if (src[i] === '\n') line++; i++; } i += 2; continue; }
    if (c === '"' || c === "'" || c === '`') {
      const q = c; const startLine = line; let buf = ''; i++;
      while (i < n && src[i] !== q) {
        if (src[i] === '\\') { buf += src[i + 1] === 'n' ? ' ' : (src[i + 1] || ''); if (src[i + 1] === '\n') line++; i += 2; continue; }
        if (src[i] === '\n') { if (q !== '`') break; line++; buf += ' '; i++; continue; }
        if (q === '`' && src[i] === '$' && src[i + 1] === '{') { flush(buf, startLine); buf = ''; let depth = 1; i += 2; while (i < n && depth) { if (src[i] === '{') depth++; else if (src[i] === '}') depth--; if (src[i] === '\n') line++; i++; } continue; }
        if (q !== '`' && src[i] === '$' && src[i + 1] === '{') { buf += '${'; i += 2; continue; }
        buf += src[i]; i++;
      }
      flush(buf, startLine); i++; continue;
    }
    i++;
  }
  return out;
}

function looksLikeCopy(t, min) {
  const s = t.trim();
  return s.length >= min && /\s/.test(s) && /[A-Za-z]{2,}/.test(s) && !/^(https?:|[./#@])/.test(s);
}

/** Findings for one file: [{ rule, line, text }]. Only errors. */
function lintFile(root, rel, cfg) {
  const raw = fs.readFileSync(path.join(root, rel), 'utf8').replace(/^﻿/, '');
  const ext = path.extname(rel).toLowerCase();
  let text; let lineMap = null;
  if (['.md', '.mdx', '.txt'].includes(ext)) text = raw;
  else if (['.html', '.htm'].includes(ext)) text = htmlText(raw);
  else if (['.js', '.mjs', '.cjs', '.jsx', '.ts', '.tsx', '.dart'].includes(ext)) {
    const srcLines = raw.split(/\r?\n/);
    const synth = []; lineMap = [];
    for (const l of literals(raw)) {
      if (!looksLikeCopy(l.text, cfg.minLiteral)) continue;
      const prev = srcLines[l.line - 2] || '';
      const at = prev.indexOf(MARK);
      if (at >= 0) { synth.push(prev.slice(at)); lineMap.push(l.line - 1); }
      synth.push(l.text.trim()); lineMap.push(l.line);
    }
    text = synth.join('\n');
  } else return [];
  const found = lint(text, { source: rel }).filter(f => f.severity === 'error');
  const lines = text.split(/\r?\n/);
  return found.map(f => ({ rule: f.rule, line: lineMap ? lineMap[f.line - 1] : f.line, text: (lines[f.line - 1] || '').trim().slice(0, 140) }));
}

const keyOf = (rel, f) => `${rel}|${f.rule}|${f.text}`;

function scan(root, cfg, only) {
  const counts = {};
  const detail = [];
  for (const rel of listFiles(root, cfg, only)) {
    let fs_;
    try { fs_ = lintFile(root, rel, cfg); } catch { continue; }
    for (const f of fs_) { const k = keyOf(rel, f); counts[k] = (counts[k] || 0) + 1; detail.push({ rel, ...f, key: k }); }
  }
  return { counts, detail };
}

function readBaseline(root) {
  try { return JSON.parse(fs.readFileSync(path.join(root, BASELINE), 'utf8').replace(/^﻿/, '')).findings || {}; } catch { return {}; }
}

/** The findings not covered by the baseline (a multiset: a baseline of 1 allows one occurrence of a key, not two). */
function newFindings(detail, baseline) {
  const left = { ...baseline };
  const out = [];
  for (const d of detail) {
    if (left[d.key] > 0) left[d.key]--; else out.push(d);
  }
  return out;
}

/** Keys whose count grew from `before` to `now`. */
function grown(before, now) {
  return Object.keys(now).filter(k => now[k] > (before[k] || 0));
}

function git(root, args) {
  return cp.spawnSync('git', args, { cwd: root, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
}

function changedSince(root, base) {
  const r = git(root, ['diff', '--name-only', '--diff-filter=ACMR', `${base}...HEAD`]);
  const r2 = r.status === 0 ? r : git(root, ['diff', '--name-only', '--diff-filter=ACMR', base, 'HEAD']);
  if (r2.status !== 0) return null;
  return new Set(r2.stdout.split(/\r?\n/).filter(Boolean));
}

function main(argv) {
  const cmd = argv[0];
  const get = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
  const root = path.resolve(get('--root', '.'));
  if (!['check', 'baseline', 'shrink'].includes(cmd)) { console.error('usage: voice-ci.js check|baseline|shrink [--root .] [--base <ref>]'); return 2; }
  const cfg = readConfig(root);
  if (cmd === 'baseline') {
    const { counts } = scan(root, cfg, null);
    fs.writeFileSync(path.join(root, BASELINE), JSON.stringify({ version: 1, findings: Object.fromEntries(Object.entries(counts).sort(([a], [b]) => a.localeCompare(b))) }, null, 2) + '\n');
    console.log(`baseline: ${Object.keys(counts).length} distinct findings (${Object.values(counts).reduce((a, b) => a + b, 0)} in all) written to ${BASELINE}`);
    return 0;
  }
  if (cmd === 'shrink') {
    const base = get('--base');
    if (!base) { console.error('shrink needs --base <ref>'); return 2; }
    const old = git(root, ['show', `${base}:${BASELINE}`]);
    const before = old.status === 0 ? (JSON.parse(old.stdout.replace(/^﻿/, '')).findings || {}) : null;
    if (before === null) { console.log(`no baseline at ${base} yet: nothing to compare`); return 0; }
    const g = grown(before, readBaseline(root));
    if (g.length) { console.error(`the baseline grew for ${g.length} finding(s); it may only shrink:`); g.slice(0, 20).forEach(k => console.error(`  ${k.slice(0, 160)}`)); return 1; }
    console.log('the baseline did not grow');
    return 0;
  }
  const base = get('--base');
  let only = null;
  if (base) { only = changedSince(root, base); if (!only) { console.error(`could not diff against ${base}; linting every included file`); } }
  const { detail } = scan(root, cfg, only);
  const fresh = newFindings(detail, readBaseline(root));
  if (!fresh.length) { console.log(`voice check: ${detail.length} finding(s), all in the baseline; none new`); return 0; }
  console.error(`voice check: ${fresh.length} NEW finding(s) (CLAUDE.md section 34):`);
  for (const f of fresh) console.error(`  ${f.rel}:${f.line}  ${f.rule}  ${f.text.slice(0, 100)}`);
  console.error('Rewrite the line, or add `voice-lint-disable-next-line <reason>` above it when the wording is deliberate.');
  return 1;
}

module.exports = { globToRe, readConfig, listFiles, htmlText, literals, looksLikeCopy, lintFile, scan, newFindings, grown, keyOf, main };

if (require.main === module) process.exitCode = main(process.argv.slice(2));
