#!/usr/bin/env node
// Bumps the version + build number in pubspec.yaml, by the branch being pushed
// (CLAUDE.md s24): dev moves the PATCH, staging the MINOR (patch resets), main
// the MAJOR (minor and patch reset). The build number always +1: Android will
// not install an update whose build number is not higher.
// Run it before a push; CI (tool/check_version.js) refuses a push that skipped it.
// Usage: node tool/bump_version.js [dev]      -> 0.3.6+16 becomes 0.3.7+17
//        node tool/bump_version.js staging    -> 0.3.6+16 becomes 0.4.0+17
//        node tool/bump_version.js main       -> 0.3.6+16 becomes 1.0.0+17
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

const branch = process.argv.slice(2).find((a) => !a.startsWith('--')) || 'dev';
const bumped = { dev: [major, minor, patch + 1], staging: [major, minor + 1, 0], main: [major + 1, 0, 0] }[branch];
if (!bumped) {
  console.error(`unknown branch "${branch}" (dev, staging or main)`);
  process.exit(1);
}
const next = `${bumped.join('.')}+${build + 1}`;
fs.writeFileSync(
  pubspecPath,
  src.replace(/^version:\s*.+$/m, `version: ${next}`)
);
console.log(next.split('+')[0]);
