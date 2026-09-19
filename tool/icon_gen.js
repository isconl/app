#!/usr/bin/env node
// Generates Android launcher icons.
// Default art: the iSconl mark - grey loop, green node on it, gap punched
// Custom art: drop a square PNG at branding/icon.png (8-bit RGB/RGBA,
// transparent background recommended) and it is adopted instead.
// Pure Node (zlib only) - no dependencies. Run: node tool/icon_gen.js
'use strict';
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');

// ---------- PNG encoder ----------
const CRC_TABLE = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  return t;
})();
function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}
function encodePng(w, h, rgba) {
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  const stride = w * 4;
  const raw = Buffer.alloc((stride + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (stride + 1)] = 0;
    rgba.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
  }
  const idat = zlib.deflateSync(raw, { level: 9 });
  return Buffer.concat([sig, chunk('IHDR', ihdr), chunk('IDAT', idat), chunk('IEND', Buffer.alloc(0))]);
}

// ---------- scene (logo.svg geometry, 256-unit design space) ----------
//
// The mark, drawn from the SAME numbers as dashboard/logo.svg and the Flutter
// painter in lib/ui/widgets/brand.dart. Three implementations of one object, so
// they share the constants and the derivation rather than three drawings that
// look similar.
//
//   centre C = (128, 128)
//   ring     R = 85 centreline, W = 42 thick   -> outer 106, inner 64
//   node     N = (196, 77), r = 30
//   gap      g = 8, hole radius = r + g = 38
//
// N is on the centreline exactly: 68^2 + 51^2 = 7225 = 85^2, which is
// 17x(3,4,5). Nothing is approximated.
//
// TWO COLOURS. The gap is a HOLE, not a fill: the node's disc is subtracted
// from the ring so the launcher background shows through it, exactly as the SVG
// mask does. Painting the gap in the background colour would look identical on
// the night ground and wrong on an adaptive-icon background of any other shade.
const BG   = [0x0d, 0x11, 0x17]; // #0d1117  launcher plate only
const RING = [0x7d, 0x85, 0x90]; // #7d8590  --text-3
const NODE = [0x3f, 0xb9, 0x50]; // #3fb950  --green

const CX = 128, CY = 128, R = 85, W = 42;
const NX = CX + 68, NY = CY - 51, NR = 30, HOLE = NR + 8;

// Returns [r,g,b,a] for a point in 256-space; layers composited in order.
function sample(x, y, opts) {
  let r = 0, g = 0, b = 0, a = 0;
  const put = (c, ca) => {
    if (ca <= 0) return;
    const na = ca + a * (1 - ca);
    r = (c[0] * ca + r * a * (1 - ca)) / na;
    g = (c[1] * ca + g * a * (1 - ca)) / na;
    b = (c[2] * ca + b * a * (1 - ca)) / na;
    a = na;
  };
  const aa = 3.0; // edge softness in design units (256-space)
  const cov = (d) => Math.max(0, Math.min(1, 0.5 - d / aa));

  if (opts.background) {
    const rr = 64, hw = 128;   // 256x256 plate, r64 - same 25% radius as before
    const qx = Math.abs(x - CX) - (hw - rr), qy = Math.abs(y - CY) - (hw - rr);
    const dOut = Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - rr;
    put(BG, cov(dOut));
  }

  const mono = opts.mono;
  const dc = Math.hypot(x - CX, y - CY);
  const dn = Math.hypot(x - NX, y - NY);

  // The ring, minus the hole. Coverage is multiplied by the INVERSE of the
  // hole's coverage, which antialiases the cut edge instead of stair-stepping
  // it - the same job the SVG mask does for free.
  const ringCov = cov(Math.abs(dc - R) - W / 2);
  const holeCov = cov(dn - HOLE);
  put(mono ? [255, 255, 255] : RING, ringCov * (1 - holeCov) * (mono ? 0.55 : 1));

  // The node.
  put(mono ? [255, 255, 255] : NODE, cov(dn - NR));

  return [r, g, b, a];
}

// Render size px canvas; art occupies `artFrac` of canvas, centered.
function render(size, { background, mono, artFrac }) {
  const ss = 3; // supersample
  const rgba = Buffer.alloc(size * size * 4);
  // Design space is 256 units now (was 64 when the art was the old favicon).
  const DESIGN = 256;
  const scale = (size * artFrac) / DESIGN;
  const off = (size - DESIGN * scale) / 2;
  for (let py = 0; py < size; py++) {
    for (let px = 0; px < size; px++) {
      let r = 0, g = 0, b = 0, a = 0;
      for (let sy = 0; sy < ss; sy++) {
        for (let sx = 0; sx < ss; sx++) {
          const x = (px + (sx + 0.5) / ss - off) / scale;
          const y = (py + (sy + 0.5) / ss - off) / scale;
          const [cr, cg, cb, ca] = sample(x, y, { background, mono });
          r += cr * ca; g += cg * ca; b += cb * ca; a += ca;
        }
      }
      const n = ss * ss;
      const i = (py * size + px) * 4;
      if (a > 0) {
        rgba[i] = Math.round(r / a);
        rgba[i + 1] = Math.round(g / a);
        rgba[i + 2] = Math.round(b / a);
      }
      rgba[i + 3] = Math.round((a / n) * 255);
    }
  }
  return encodePng(size, size, rgba);
}

// ---------- optional custom source (branding/icon.png) ----------
function paeth(a, b, c) {
  const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
  return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
}
function decodePng(buf) {
  if (buf.readUInt32BE(0) !== 0x89504e47) throw new Error('not a PNG');
  let pos = 8, w = 0, h = 0, bitDepth = 0, colorType = 0, interlace = 0;
  const idat = [];
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos);
    const type = buf.toString('ascii', pos + 4, pos + 8);
    const data = buf.subarray(pos + 8, pos + 8 + len);
    if (type === 'IHDR') {
      w = data.readUInt32BE(0); h = data.readUInt32BE(4);
      bitDepth = data[8]; colorType = data[9]; interlace = data[12];
    } else if (type === 'IDAT') idat.push(data);
    else if (type === 'IEND') break;
    pos += 12 + len;
  }
  if (bitDepth !== 8 || (colorType !== 6 && colorType !== 2) || interlace) {
    throw new Error('branding/icon.png must be 8-bit RGB or RGBA, non-interlaced');
  }
  const bpp = colorType === 6 ? 4 : 3;
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = w * bpp;
  const out = Buffer.alloc(w * h * 4);
  const prev = Buffer.alloc(stride);
  for (let y = 0; y < h; y++) {
    const filter = raw[y * (stride + 1)];
    const line = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    for (let x = 0; x < stride; x++) {
      const left = x >= bpp ? line[x - bpp] : 0;
      const up = prev[x];
      const ul = x >= bpp ? prev[x - bpp] : 0;
      switch (filter) {
        case 1: line[x] = (line[x] + left) & 0xff; break;
        case 2: line[x] = (line[x] + up) & 0xff; break;
        case 3: line[x] = (line[x] + ((left + up) >> 1)) & 0xff; break;
        case 4: line[x] = (line[x] + paeth(left, up, ul)) & 0xff; break;
      }
    }
    line.copy(prev);
    for (let x = 0; x < w; x++) {
      const si = x * bpp, di = (y * w + x) * 4;
      out[di] = line[si]; out[di + 1] = line[si + 1]; out[di + 2] = line[si + 2];
      out[di + 3] = bpp === 4 ? line[si + 3] : 255;
    }
  }
  return { width: w, height: h, rgba: out };
}
// Bilinear sample of the custom image in premultiplied space.
function sampleImage(img, u, v) {
  if (u < 0 || v < 0 || u > 1 || v > 1) return [0, 0, 0, 0];
  const fx = u * (img.width - 1), fy = v * (img.height - 1);
  const x0 = Math.floor(fx), y0 = Math.floor(fy);
  const x1 = Math.min(x0 + 1, img.width - 1), y1 = Math.min(y0 + 1, img.height - 1);
  const tx = fx - x0, ty = fy - y0;
  const px = (x, y) => {
    const i = (y * img.width + x) * 4;
    const a = img.rgba[i + 3] / 255;
    return [img.rgba[i] * a, img.rgba[i + 1] * a, img.rgba[i + 2] * a, a];
  };
  const mix = (p, q, t) => p.map((v0, i) => v0 + (q[i] - v0) * t);
  const top = mix(px(x0, y0), px(x1, y0), tx);
  const bot = mix(px(x0, y1), px(x1, y1), tx);
  const [r, g, b, a] = mix(top, bot, ty);
  return a > 0 ? [r / a, g / a, b / a, a] : [0, 0, 0, 0];
}
function renderFromImage(img, size, { background, mono, artFrac }) {
  const rgba = Buffer.alloc(size * size * 4);
  const art = size * artFrac;
  const off = (size - art) / 2;
  for (let py = 0; py < size; py++) {
    for (let px2 = 0; px2 < size; px2++) {
      let [r, g, b, a] = sampleImage(img, (px2 - off) / art, (py - off) / art);
      if (mono) { r = 255; g = 255; b = 255; }
      if (background && a < 1) {
        r = r * a + BG[0] * (1 - a);
        g = g * a + BG[1] * (1 - a);
        b = b * a + BG[2] * (1 - a);
        a = 1;
      }
      const i = (py * size + px2) * 4;
      rgba[i] = Math.round(r); rgba[i + 1] = Math.round(g);
      rgba[i + 2] = Math.round(b); rgba[i + 3] = Math.round(a * 255);
    }
  }
  return encodePng(size, size, rgba);
}

const brandingPath = path.join(__dirname, '..', 'branding', 'icon.png');
let custom = null;
if (fs.existsSync(brandingPath)) {
  try {
    custom = decodePng(fs.readFileSync(brandingPath));
    console.log('using custom branding/icon.png', `${custom.width}x${custom.height}`);
  } catch (e) {
    console.warn('branding/icon.png ignored:', e.message, '- using default art');
  }
}
const draw = (size, opts) =>
  custom ? renderFromImage(custom, size, opts) : render(size, opts);

const res = path.join(__dirname, '..', 'android', 'app', 'src', 'main', 'res');
const densities = { mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4 };
for (const [d, m] of Object.entries(densities)) {
  const dir = path.join(res, `mipmap-${d}`);
  fs.mkdirSync(dir, { recursive: true });
  // legacy launcher icon: art with baked background
  fs.writeFileSync(path.join(dir, 'ic_launcher.png'), draw(Math.round(48 * m), { background: true, mono: false, artFrac: 1 }));
  // adaptive layers (108dp canvas, art within ~62% for the 66dp safe zone)
  fs.writeFileSync(path.join(dir, 'ic_launcher_foreground.png'), draw(Math.round(108 * m), { background: false, mono: false, artFrac: 0.56 }));
  fs.writeFileSync(path.join(dir, 'ic_launcher_monochrome.png'), draw(Math.round(108 * m), { background: false, mono: true, artFrac: 0.56 }));
}
const anydpi = path.join(res, 'mipmap-anydpi-v26');
fs.mkdirSync(anydpi, { recursive: true });
fs.writeFileSync(path.join(anydpi, 'ic_launcher.xml'), `<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>
</adaptive-icon>
`);
const values = path.join(res, 'values');
fs.mkdirSync(values, { recursive: true });
fs.writeFileSync(path.join(values, 'ic_launcher_background.xml'), `<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#0d1117</color>
</resources>
`);
console.log('icons written to', res);
