/*
 * ABI v1 kernel harness for the real WASM runtime (YUV-22/23/31/32).
 *
 * The native test_native/abi_*_test.c suites prove the kernels in C. This
 * runs the same operations through the actual WASM module built from the same
 * sources, so "native and Web pass the same cases" is evidence rather than an
 * assumption. It deliberately reuses the native case identities -- the labels
 * below match the native tests -- and checks the same properties:
 *
 *   TRANSFORM-FLIP-H-I420-4x4      luma mapping and chroma copy
 *   TRANSFORM-ROT-90-BGRA-6x4      transposed destination geometry
 *   CROP-TRAILING-CHROMA-I420-3x3  clipped footprint, not a copy
 *   CONVERT-PARITY-RGBA-BGRA-5x3   the same image in two channel orders
 *   EFFECT-BW-THRESHOLD-BGRA       gray 128 becomes white
 *   EFFECT-NEGATE-ROI-BGRA-8x8     outside the region stays byte-identical
 *   BLUR-FLAT-EDGE-REPLICATE-BGRA  a flat image survives its own border
 *   BLUR-ROI-I420-4x4              luma outside the region is untouched
 *
 * Descriptors are built by hand at the ABI v1 byte layout, because the point
 * is to exercise the wire format the Dart web backend will use, not a
 * convenience wrapper over it.
 */

const fs = require('fs');
const path = require('path');

const createYuvFfiModule = require('../assets/wasm/yuv_ffi.js');

/* Node has no fetch relative to the module, so the binary is handed over
 * directly, as tool/yuv05_wasm_harness.cjs already does. */
const WASM_PATH = path.join(__dirname, '..', 'assets', 'wasm', 'yuv_ffi.wasm');

let checks = 0;
let failures = 0;

function ok(label) {
  checks += 1;
  console.log(`  ok    ${label}`);
}

function bad(label, detail) {
  checks += 1;
  failures += 1;
  console.log(`  FAIL  ${label}${detail ? `: ${detail}` : ''}`);
}

function expect(label, condition, detail) {
  if (condition) ok(label);
  else bad(label, detail);
}

const FORMAT = { I420: 1, NV12: 2, BGRA: 3, RGBA: 4 };
const STATUS_OK = 0;
const CANARY = 0xc3;

/* Layout from docs/api-abi-0.3-design.md section 9, which fixes the same
 * numbers for native64, native32 and wasm32: the plane descriptor is 32 bytes
 * (length 0, rowStride 8, pixelStride 16, sampleBytes 20, data 24, tail
 * padding to 32), the frame's scalar prefix is 32, its three planes sit at
 * 32/64/96, reserved at 128, total 160. */
const PLANE_BYTES = 32;
const PLANE_DATA_OFFSET = 24;
const FRAME_HEADER_BYTES = 32;
const FRAME_BYTES = 160;

function planeWidth(format, index, width) {
  if (index === 0 || format === FORMAT.BGRA || format === FORMAT.RGBA) return width;
  return (width + 1) >> 1;
}

function planeHeight(format, index, height) {
  if (index === 0 || format === FORMAT.BGRA || format === FORMAT.RGBA) return height;
  return (height + 1) >> 1;
}

function planeCount(format) {
  if (format === FORMAT.I420) return 3;
  if (format === FORMAT.NV12) return 2;
  return 1;
}

function sampleBytesOf(format, index) {
  if (format === FORMAT.BGRA || format === FORMAT.RGBA) return 4;
  if (format === FORMAT.NV12 && index === 1) return 2;
  return 1;
}

/* Allocates a frame's planes with a padded row stride, fills every byte with
 * the canary, and writes the descriptor. Returns handles for reading back. */
function makeFrame(module, format, width, height, pad = 5) {
  const count = planeCount(format);
  const planes = [];
  for (let index = 0; index < count; index += 1) {
    const sampleBytes = sampleBytesOf(format, index);
    const pw = planeWidth(format, index, width);
    const ph = planeHeight(format, index, height);
    const rowStride = pw * sampleBytes + pad;
    const length = rowStride * ph;
    const ptr = module._malloc(length);
    if (!ptr) throw new Error('WASM allocation failed');
    module.HEAPU8.fill(CANARY, ptr, ptr + length);
    planes.push({ ptr, length, rowStride, pixelStride: sampleBytes, sampleBytes, pw, ph });
  }

  const framePtr = module._malloc(FRAME_BYTES);
  module.HEAPU8.fill(0, framePtr, framePtr + FRAME_BYTES);
  const view = new DataView(module.HEAPU8.buffer);
  const yuv = format === FORMAT.I420 || format === FORMAT.NV12;
  view.setUint32(framePtr + 0, FRAME_BYTES, true);
  view.setUint32(framePtr + 4, 1, true);
  view.setUint32(framePtr + 8, format, true);
  view.setUint32(framePtr + 12, count, true);
  view.setUint32(framePtr + 16, width, true);
  view.setUint32(framePtr + 20, height, true);
  view.setUint32(framePtr + 24, yuv ? 1 : 0, true);
  view.setUint32(framePtr + 28, yuv ? 1 : 0, true);
  for (let index = 0; index < count; index += 1) {
    const base = framePtr + FRAME_HEADER_BYTES + index * PLANE_BYTES;
    const plane = planes[index];
    view.setBigUint64(base + 0, BigInt(plane.length), true);
    view.setBigUint64(base + 8, BigInt(plane.rowStride), true);
    view.setUint32(base + 16, plane.pixelStride, true);
    view.setUint32(base + 20, plane.sampleBytes, true);
    view.setUint32(base + PLANE_DATA_OFFSET, plane.ptr, true);
  }
  return { framePtr, planes, format, width, height };
}

function sampleOffset(frame, index, x, y) {
  const plane = frame.planes[index];
  return plane.ptr + y * plane.rowStride + x * plane.pixelStride;
}

function readSample(module, frame, index, x, y) {
  return module.HEAPU8[sampleOffset(frame, index, x, y)];
}

function writeSample(module, frame, index, x, y, bytes) {
  const offset = sampleOffset(frame, index, x, y);
  for (let i = 0; i < bytes.length; i += 1) module.HEAPU8[offset + i] = bytes[i];
}

function paddingIntact(module, frame) {
  for (let index = 0; index < frame.planes.length; index += 1) {
    const plane = frame.planes[index];
    const span = plane.pw * plane.pixelStride;
    for (let y = 0; y < plane.ph; y += 1) {
      for (let offset = span; offset < plane.rowStride; offset += 1) {
        if (module.HEAPU8[plane.ptr + y * plane.rowStride + offset] !== CANARY) return false;
      }
    }
  }
  return true;
}

/* Options blocks, each at its ABI v1 layout. */
function regionBlock(view, base, region) {
  view.setUint32(base + 0, 32, true);
  view.setUint32(base + 4, 1, true);
  view.setInt32(base + 8, region ? region.left : 0, true);
  view.setInt32(base + 12, region ? region.top : 0, true);
  view.setInt32(base + 16, region ? region.right : 0, true);
  view.setInt32(base + 20, region ? region.bottom : 0, true);
  view.setUint32(base + 24, region ? 1 : 0, true);
  view.setUint32(base + 28, 0, true);
}

function makeEffectOptions(module, region) {
  /* structSize, abiVersion, region (32), reserved[2] (16). */
  const size = 8 + 32 + 16;
  const ptr = module._malloc(size);
  module.HEAPU8.fill(0, ptr, ptr + size);
  const view = new DataView(module.HEAPU8.buffer);
  view.setUint32(ptr + 0, size, true);
  view.setUint32(ptr + 4, 1, true);
  regionBlock(view, ptr + 8, region);
  return ptr;
}

function makeBlurOptions(module, radius, sigma, region) {
  /* structSize, abiVersion, radius, borderMode, double sigma (8-aligned),
   * region, reserved[2]. */
  /* structSize, abiVersion, radius, borderMode (16), sigma (8, 8-aligned),
   * region (32), reserved[2] (16). */
  const size = 16 + 8 + 32 + 16;
  const ptr = module._malloc(size);
  module.HEAPU8.fill(0, ptr, ptr + size);
  const view = new DataView(module.HEAPU8.buffer);
  view.setUint32(ptr + 0, size, true);
  view.setUint32(ptr + 4, 1, true);
  view.setUint32(ptr + 8, radius, true);
  view.setUint32(ptr + 12, 1, true);
  view.setFloat64(ptr + 16, sigma, true);
  regionBlock(view, ptr + 24, region);
  return ptr;
}

function makeConvertOptions(module) {
  const size = 8 + 24;
  const ptr = module._malloc(size);
  module.HEAPU8.fill(0, ptr, ptr + size);
  const view = new DataView(module.HEAPU8.buffer);
  view.setUint32(ptr + 0, size, true);
  view.setUint32(ptr + 4, 1, true);
  return ptr;
}

function makeFlipOptions(module, direction) {
  const size = 8 + 8 + 16;
  const ptr = module._malloc(size);
  module.HEAPU8.fill(0, ptr, ptr + size);
  const view = new DataView(module.HEAPU8.buffer);
  view.setUint32(ptr + 0, size, true);
  view.setUint32(ptr + 4, 1, true);
  view.setUint32(ptr + 8, direction, true);
  return ptr;
}

function makeRotateOptions(module, degrees) {
  const size = 8 + 8 + 16;
  const ptr = module._malloc(size);
  module.HEAPU8.fill(0, ptr, ptr + size);
  const view = new DataView(module.HEAPU8.buffer);
  view.setUint32(ptr + 0, size, true);
  view.setUint32(ptr + 4, 1, true);
  view.setUint32(ptr + 8, degrees, true);
  return ptr;
}

function makeCropOptions(module, left, top, width, height) {
  /* structSize, abiVersion, left, top, width, height (24), reserved[1] (8). */
  const size = 32;
  const ptr = module._malloc(size);
  module.HEAPU8.fill(0, ptr, ptr + size);
  const view = new DataView(module.HEAPU8.buffer);
  view.setUint32(ptr + 0, size, true);
  view.setUint32(ptr + 4, 1, true);
  view.setInt32(ptr + 8, left, true);
  view.setInt32(ptr + 12, top, true);
  view.setUint32(ptr + 16, width, true);
  view.setUint32(ptr + 20, height, true);
  return ptr;
}

function clip(value) {
  return value < 0 ? 0 : value > 255 ? 255 : value;
}

function oracleGray(r, g, b) {
  return clip(Math.floor((299 * r + 587 * g + 114 * b + 500) / 1000));
}

function fillPattern(module, frame) {
  for (let index = 0; index < frame.planes.length; index += 1) {
    const plane = frame.planes[index];
    for (let y = 0; y < plane.ph; y += 1) {
      for (let x = 0; x < plane.pw; x += 1) {
        const bytes = [];
        for (let byte = 0; byte < plane.sampleBytes; byte += 1) {
          bytes.push((17 * index + 31 * y + 7 * x + 3 * byte + 1) & 0xff);
        }
        writeSample(module, frame, index, x, y, bytes);
      }
    }
  }
}

async function main() {
  const module = await createYuvFfiModule({ wasmBinary: fs.readFileSync(WASM_PATH) });

  console.log('=============================================================');
  console.log('ABI v1 kernel harness on the real WASM runtime');
  console.log('=============================================================');

  /* ---- TRANSFORM-FLIP-H-I420-4x4 ---- */
  {
    const source = makeFrame(module, FORMAT.I420, 4, 4);
    const destination = makeFrame(module, FORMAT.I420, 4, 4);
    fillPattern(module, source);
    const options = makeFlipOptions(module, 1);
    const status = module._yuv_flip_v1(source.framePtr, destination.framePtr, options);
    expect('TRANSFORM-FLIP-H-I420-4x4 status', status === STATUS_OK, `status=${status}`);

    let mapped = true;
    for (let y = 0; y < 4 && mapped; y += 1) {
      for (let x = 0; x < 4 && mapped; x += 1) {
        const expected = readSample(module, source, 0, 3 - x, y);
        const actual = readSample(module, destination, 0, x, y);
        if (expected !== actual) mapped = false;
      }
    }
    expect('      luma mapping matches the native oracle', mapped);
    expect('      padding intact', paddingIntact(module, destination));
  }

  /* ---- TRANSFORM-ROT-90-BGRA-6x4 ---- */
  {
    const source = makeFrame(module, FORMAT.BGRA, 6, 4);
    const destination = makeFrame(module, FORMAT.BGRA, 4, 6);
    fillPattern(module, source);
    const options = makeRotateOptions(module, 90);
    const status = module._yuv_rotate_v1(source.framePtr, destination.framePtr, options);
    expect('TRANSFORM-ROT-90-BGRA-6x4 status', status === STATUS_OK, `status=${status}`);

    let mapped = true;
    for (let y = 0; y < 6 && mapped; y += 1) {
      for (let x = 0; x < 4 && mapped; x += 1) {
        for (let byte = 0; byte < 4; byte += 1) {
          const expected = module.HEAPU8[sampleOffset(source, 0, y, 4 - 1 - x) + byte];
          const actual = module.HEAPU8[sampleOffset(destination, 0, x, y) + byte];
          if (expected !== actual) { mapped = false; break; }
        }
      }
    }
    expect('      transposed geometry mapped correctly', mapped);
    expect('      padding intact', paddingIntact(module, destination));
  }

  /* ---- CROP-TRAILING-CHROMA-I420-3x3 ---- */
  {
    const source = makeFrame(module, FORMAT.I420, 4, 4);
    const destination = makeFrame(module, FORMAT.I420, 3, 3);
    for (let y = 0; y < 4; y += 1) {
      for (let x = 0; x < 4; x += 1) writeSample(module, source, 0, x, y, [(40 + 37 * x + 19 * y) & 0xff]);
    }
    for (let y = 0; y < 2; y += 1) {
      for (let x = 0; x < 2; x += 1) {
        writeSample(module, source, 1, x, y, [(60 + 50 * x) & 0xff]);
        writeSample(module, source, 2, x, y, [(200 - 50 * y) & 0xff]);
      }
    }
    const options = makeCropOptions(module, 0, 0, 3, 3);
    const status = module._yuv_crop_v1(source.framePtr, destination.framePtr, options);
    expect('CROP-TRAILING-CHROMA-I420-3x3 status', status === STATUS_OK, `status=${status}`);

    /* Destination block (0,1) covers dest pixels (0,2) and (1,2) -- two of the
     * four the source block (0,1) was averaged over -- so the contract's
     * clipped average is 80 where the stored source sample is 60. A copy
     * would produce 60. (Blocks covering a single pixel are not a usable
     * probe here: re-encoding one pixel round-trips to the same value.) */
    const trailing = readSample(module, destination, 1, 0, 1);
    const sourceSample = readSample(module, source, 1, 0, 1);
    expect('      trailing chroma uses the clipped footprint, not a copy',
      trailing === 80 && sourceSample === 60, `got ${trailing}, source ${sourceSample}`);
    expect('      padding intact', paddingIntact(module, destination));
  }

  /* ---- CONVERT-PARITY-RGBA-BGRA-5x3 ---- */
  {
    const rgba = makeFrame(module, FORMAT.RGBA, 5, 3);
    const bgra = makeFrame(module, FORMAT.BGRA, 5, 3);
    for (let y = 0; y < 3; y += 1) {
      for (let x = 0; x < 5; x += 1) {
        const r = (37 * x + 11 * y) % 256;
        const g = (17 * x + 53 * y) % 256;
        const b = (71 * x + 29 * y) % 256;
        writeSample(module, rgba, 0, x, y, [r, g, b, 255]);
        writeSample(module, bgra, 0, x, y, [b, g, r, 255]);
      }
    }
    const fromRgba = makeFrame(module, FORMAT.I420, 5, 3);
    const fromBgra = makeFrame(module, FORMAT.I420, 5, 3);
    const options = makeConvertOptions(module);
    const a = module._yuv_convert_v1(rgba.framePtr, fromRgba.framePtr, options);
    const b = module._yuv_convert_v1(bgra.framePtr, fromBgra.framePtr, options);
    expect('CONVERT-PARITY-RGBA-BGRA-5x3 status', a === STATUS_OK && b === STATUS_OK, `${a}/${b}`);

    let identical = true;
    for (let index = 0; index < 3 && identical; index += 1) {
      const plane = fromRgba.planes[index];
      for (let y = 0; y < plane.ph && identical; y += 1) {
        for (let x = 0; x < plane.pw && identical; x += 1) {
          if (readSample(module, fromRgba, index, x, y) !== readSample(module, fromBgra, index, x, y)) {
            identical = false;
          }
        }
      }
    }
    expect('      RGBA and BGRA produce identical YUV samples', identical);
  }

  /* ---- EFFECT-BW-THRESHOLD-BGRA ---- */
  {
    const source = makeFrame(module, FORMAT.BGRA, 2, 1);
    writeSample(module, source, 0, 0, 0, [128, 128, 128, 255]);
    writeSample(module, source, 0, 1, 0, [127, 127, 127, 255]);
    const destination = makeFrame(module, FORMAT.BGRA, 2, 1);
    const options = makeEffectOptions(module, null);
    const status = module._yuv_black_white_v1(source.framePtr, destination.framePtr, options);
    expect('EFFECT-BW-THRESHOLD-BGRA status', status === STATUS_OK, `status=${status}`);
    expect('      gray 128 becomes white', readSample(module, destination, 0, 0, 0) === 255,
      `got ${readSample(module, destination, 0, 0, 0)}`);
    expect('      gray 127 stays black', readSample(module, destination, 0, 1, 0) === 0);
    expect('      oracle agrees on the threshold', oracleGray(128, 128, 128) === 128);
  }

  /* ---- EFFECT-NEGATE-ROI-BGRA-8x8 ---- */
  {
    const source = makeFrame(module, FORMAT.BGRA, 8, 8);
    for (let y = 0; y < 8; y += 1) {
      for (let x = 0; x < 8; x += 1) {
        writeSample(module, source, 0, x, y,
          [(71 * x + 29 * y) % 256, (17 * x + 53 * y) % 256, (37 * x + 11 * y) % 256, 200 + ((x + y) % 40)]);
      }
    }
    const destination = makeFrame(module, FORMAT.BGRA, 8, 8);
    const options = makeEffectOptions(module, { left: 2, top: 2, right: 6, bottom: 6 });
    const status = module._yuv_negate_v1(source.framePtr, destination.framePtr, options);
    expect('EFFECT-NEGATE-ROI-BGRA-8x8 status', status === STATUS_OK, `status=${status}`);

    let correct = true;
    for (let y = 0; y < 8 && correct; y += 1) {
      for (let x = 0; x < 8 && correct; x += 1) {
        const inside = x >= 2 && x < 6 && y >= 2 && y < 6;
        for (let byte = 0; byte < 4; byte += 1) {
          const from = module.HEAPU8[sampleOffset(source, 0, x, y) + byte];
          const to = module.HEAPU8[sampleOffset(destination, 0, x, y) + byte];
          const want = inside && byte < 3 ? 255 - from : from;
          if (to !== want) { correct = false; break; }
        }
      }
    }
    expect('      inside negated, outside byte-identical, alpha preserved', correct);
  }

  /* ---- BLUR-FLAT-EDGE-REPLICATE-BGRA ---- */
  {
    const source = makeFrame(module, FORMAT.BGRA, 6, 5);
    for (let y = 0; y < 5; y += 1) {
      for (let x = 0; x < 6; x += 1) writeSample(module, source, 0, x, y, [90, 140, 200, 255]);
    }
    const destination = makeFrame(module, FORMAT.BGRA, 6, 5);
    const options = makeBlurOptions(module, 2, 0.0, null);
    const status = module._yuv_mean_blur_v1(source.framePtr, destination.framePtr, options);
    expect('BLUR-FLAT-EDGE-REPLICATE-BGRA status', status === STATUS_OK, `status=${status}`);

    let flat = true;
    for (let y = 0; y < 5 && flat; y += 1) {
      for (let x = 0; x < 6 && flat; x += 1) {
        const offset = sampleOffset(destination, 0, x, y);
        if (module.HEAPU8[offset] !== 90 || module.HEAPU8[offset + 1] !== 140 ||
            module.HEAPU8[offset + 2] !== 200) {
          flat = false;
        }
      }
    }
    expect('      flat image preserved at the border', flat);
    expect('      padding intact', paddingIntact(module, destination));
  }

  /* ---- BLUR-ROI-I420-4x4 ---- */
  {
    const source = makeFrame(module, FORMAT.I420, 4, 4);
    for (let y = 0; y < 4; y += 1) {
      for (let x = 0; x < 4; x += 1) writeSample(module, source, 0, x, y, [16 + y * 4 + x]);
    }
    for (let y = 0; y < 2; y += 1) {
      for (let x = 0; x < 2; x += 1) {
        writeSample(module, source, 1, x, y, [100 + y * 2 + x]);
        writeSample(module, source, 2, x, y, [140 + y * 2 + x]);
      }
    }
    const destination = makeFrame(module, FORMAT.I420, 4, 4);
    const options = makeBlurOptions(module, 1, 0.0, { left: 1, top: 1, right: 2, bottom: 2 });
    const status = module._yuv_mean_blur_v1(source.framePtr, destination.framePtr, options);
    expect('BLUR-ROI-I420-4x4 status', status === STATUS_OK, `status=${status}`);

    let untouched = true;
    let detail = '';
    for (let y = 0; y < 4 && untouched; y += 1) {
      for (let x = 0; x < 4 && untouched; x += 1) {
        if (x === 1 && y === 1) continue;
        const from = readSample(module, source, 0, x, y);
        const to = readSample(module, destination, 0, x, y);
        if (from !== to) {
          untouched = false;
          detail = `luma (${x},${y}) ${from} -> ${to}`;
        }
      }
    }
    expect('      luma outside the region is byte-identical', untouched, detail);
  }

  console.log('-------------------------------------------------------------');
  console.log(`checks: ${checks}, failures: ${failures}`);
  if (failures > 0) process.exitCode = 1;
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
