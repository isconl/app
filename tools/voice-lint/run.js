'use strict';
/**
 * BI26092602: `node tools/voice-lint/run.js [--strict] [--extractor <file>]`
 *
 * Extracts the repo's user-visible copy, lints it with the vendored voice-lint, prints a summary and (in GitHub
 * Actions) one warning annotation per finding. WARNING-ONLY by default: exit 0 whatever it finds, so the step can
 * ship before the comb row has cleaned the existing copy. `--strict` fails on any error finding; flip the workflow to
 * it once the comb is done.
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const args = process.argv.slice(2);
const strict = args.includes('--strict');
const xi = args.indexOf('--extractor');
const extractorPath = path.resolve(xi >= 0 ? args[xi + 1] : path.join(__dirname, 'extract-hub.js'));
const root = path.resolve(__dirname, '..', '..');

const { extract } = require(extractorPath);
const strings = extract(root);
const tmp = path.join(os.tmpdir(), `voice-copy-${process.pid}.json`);
fs.writeFileSync(tmp, JSON.stringify(strings));
const r = spawnSync(process.execPath, [path.join(__dirname, 'voice-lint.js'), '--json', tmp, '--format', 'json'], { encoding: 'utf8' });
fs.rmSync(tmp, { force: true });
if (r.status === 2 || r.status === 3 || (r.status !== 0 && r.status !== 1)) {
  console.error(`voice-lint could not run (exit ${r.status}): ${String(r.stderr || '').slice(0, 300)}`);
  process.exit(2);
}
let findings = [];
try { findings = JSON.parse(r.stdout || '[]'); } catch { console.error('voice-lint produced output that is not JSON'); process.exit(2); }

const errors = findings.filter((f) => f.severity === 'error');
const byRule = {};
for (const f of findings) byRule[f.rule] = (byRule[f.rule] || 0) + 1;
console.log(`voice-lint: ${strings.length} strings checked, ${findings.length} finding(s) (${errors.length} error)`);
for (const [rule, n] of Object.entries(byRule).sort()) console.log(`  ${rule}: ${n}`);
for (const f of findings) {
  const id = String(f.source).replace(/^.*\[/, '').replace(/\]$/, '');
  const [file, line] = id.split(':');
  const msg = `${f.rule}: ${f.message} ("${String(f.snippet).slice(0, 60)}")`;
  if (process.env.GITHUB_ACTIONS) console.log(`::${strict ? 'error' : 'warning'} file=${file},line=${line || 1}::${msg}`);
  else console.log(`  ${id}  ${msg}`);
}
process.exit(strict && errors.length ? 1 : 0);
