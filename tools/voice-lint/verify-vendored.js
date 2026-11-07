'use strict';
// BI26092602: fail if a vendored voice-lint file was edited here instead of in _kit/bin.
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const dir = __dirname;
const source = JSON.parse(fs.readFileSync(path.join(dir, 'SOURCE.json'), 'utf8'));
let bad = 0;
for (const [name, want] of Object.entries(source.sha256)) {
  const got = crypto.createHash('sha256').update(fs.readFileSync(path.join(dir, name), 'utf8').replace(/\r\n/g, '\n')).digest('hex');
  if (got !== want) { console.error(`${name} no longer matches the hash recorded when it was vendored: change the _kit copy and re-vendor`); bad = 1; }
}
console.log(bad ? 'voice-lint vendored files: DRIFT' : 'voice-lint vendored files: match');
process.exit(bad);