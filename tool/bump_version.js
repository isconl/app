#!/usr/bin/env node
// Bumps the patch version + build number in pubspec.yaml.
// CI runs this on every build so each APK release is uniquely versioned.
// Usage: node tool/bump_version.js            -> 0.0.4+5 becomes 0.0.5+6
//        node tool/bump_version.js --print    -> just print current version
'use strict';
const fs = require('fs');
const path = require('path');

const pubspecPath = path.join(__dirname, '..', 'pubspec.yaml');
const src = fs.readFileSync(pubspecPath, 'utf8');
const match = src.match(/^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$/m);
if (!match) {
  console.error('version line not found in pubspec.yaml');
  process.exit(1);
}
const [, major, minor, patch, build] = match.map(Number);

if (process.argv.includes('--print')) {
  console.log(`${major}.${minor}.${patch}`);
  process.exit(0);
}

const next = `${major}.${minor}.${patch + 1}+${build + 1}`;
fs.writeFileSync(
  pubspecPath,
  src.replace(/^version:\s*.+$/m, `version: ${next}`)
);
console.log(next.split('+')[0]);
