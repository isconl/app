#!/usr/bin/env node
// Refuses a release whose version did not move the digit the branch owns
// (CLAUDE.md s24): dev -> patch, staging -> minor (patch 0), main -> major
// (minor and patch 0), and the build number must rise. "A version that did not
// move is a claim that nothing shipped."
// Usage: node tool/check_version.js <branch> [--latest X.Y.Z+B]
// Without --latest it reads the newest apk-v* tag and that tag's pubspec.
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const parse = (t) => {
  const m = /^(\d+)\.(\d+)\.(\d+)\+(\d+)$/.exec(t.trim());
  return m ? m.slice(1).map(Number) : null;
};
const fail = (msg) => { console.error(`::error::${msg}`); process.exit(1); };

const branch = process.argv[2];
if (!['dev', 'staging', 'main'].includes(branch)) fail(`branch "${branch}" is not dev, staging or main`);

const pub = fs.readFileSync(path.join(__dirname, '..', 'pubspec.yaml'), 'utf8').match(/^version:\s*(\S+)\s*$/m);
const cur = pub && parse(pub[1]);
if (!cur) fail('pubspec.yaml has no MAJOR.MINOR.PATCH+BUILD version');

let latest;
const li = process.argv.indexOf('--latest');
if (li > 0) {
  latest = parse(process.argv[li + 1]);
} else {
  const run = (a) => execFileSync('git', a, { encoding: 'utf8' }).trim();
  const tags = run(['tag', '--list', 'apk-v*']).split('\n').filter(Boolean)
    .map((t) => ({ t, v: t.slice(5).split('.').map(Number) }))
    .sort((a, b) => a.v[0] - b.v[0] || a.v[1] - b.v[1] || a.v[2] - b.v[2]);
  if (!tags.length) { console.log('no earlier release; nothing to compare'); process.exit(0); }
  const tag = tags[tags.length - 1].t;
  const old = run(['show', `${tag}:pubspec.yaml`]).match(/^version:\s*(\S+)\s*$/m);
  latest = old && parse(old[1]);
}
if (!latest) fail('could not read the latest released version');

const [cM, cm, cp, cb] = cur, [lM, lm, lp, lb] = latest;
const rule = {
  dev: cM === lM && cm === lm && cp > lp,
  staging: cM === lM && cm > lm && cp === 0,
  main: cM > lM && cm === 0 && cp === 0,
}[branch];
const want = { dev: 'the patch to rise, major and minor unchanged', staging: 'the minor to rise with patch 0', main: 'the major to rise with minor and patch 0' }[branch];
if (!rule) fail(`${branch} pushes must move ${want}: released ${lM}.${lm}.${lp}+${lb}, pubspec says ${cM}.${cm}.${cp}+${cb}. Run: node tool/bump_version.js ${branch}`);
if (cb <= lb) fail(`build number must rise (released +${lb}, pubspec +${cb}); Android will not install a lower one`);
console.log(`ok: ${cM}.${cm}.${cp}+${cb} follows ${lM}.${lm}.${lp}+${lb} on ${branch}`);
