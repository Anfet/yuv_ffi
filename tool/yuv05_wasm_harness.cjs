const fs = require('fs');
const path = require('path');

const createYuvFfiModule = require('../assets/wasm/yuv_ffi.js');

function fail(message) {
  throw new Error(message);
}

function isLogicalOffset(offset, logicalWidth, pixelStride, sampleBytes) {
  for (let column = 0; column < logicalWidth; column += 1) {
    const start = column * pixelStride;
    if (offset >= start && offset < start + sampleBytes) return true;
  }
  return false;
}

function expectPadding(module, label, ptr, height, rowStride, logicalWidth, pixelStride, sampleBytes) {
  for (let row = 0; row < height; row += 1) {
    for (let offset = 0; offset < rowStride; offset += 1) {
      if (!isLogicalOffset(offset, logicalWidth, pixelStride, sampleBytes)) {
        const actual = module.HEAPU8[ptr + row * rowStride + offset];
        if (actual !== 0xa5) fail(`${label} padding changed at row=${row} offset=${offset}: ${actual}`);
      }
    }
  }
}

function expectByte(label, actual, expected, row, column) {
  if (actual !== expected) fail(`${label} mismatch at row=${row} column=${column}: ${actual} != ${expected}`);
}

function allocate(module, length, fill = 0xa5) {
  const ptr = module._malloc(length);
  if (!ptr) fail(`WASM allocation failed for ${length} bytes`);
  module.HEAPU8.fill(fill, ptr, ptr + length);
  return ptr;
}

function writeDef(module, fields) {
  const ptr = allocate(module, 9 * 4, 0);
  const base = ptr >>> 2;
  const values = [
    fields.y,
    fields.u || 0,
    fields.v || 0,
    fields.width,
    fields.height,
    fields.yRowStride,
    fields.yPixelStride,
    fields.uvRowStride,
    fields.uvPixelStride,
  ];
  values.forEach((value, index) => {
    module.HEAP32[base + index] = value;
  });
  return ptr;
}

function call(module, name, args) {
  module.ccall(name, 'void', args.map(() => 'number'), args);
}

function runSize(module, width, height) {
  const chromaWidth = Math.ceil(width / 2);
  const chromaHeight = Math.ceil(height / 2);
  const yPixelStride = 3;
  const yRowStride = (width - 1) * yPixelStride + 1 + 5;
  const uvPixelStride = 2;
  const i420UvRowStride = (chromaWidth - 1) * uvPixelStride + 1 + 5;
  const nvUvRowStride = chromaWidth * 2 + 5;
  const allocations = [];
  const alloc = (length, fill) => {
    const ptr = allocate(module, length, fill);
    allocations.push(ptr);
    return ptr;
  };

  try {
    const rgba = alloc(width * height * 4, 0);
    for (let index = 0; index < width * height * 4; index += 4) {
      module.HEAPU8[index + rgba] = 255;
      module.HEAPU8[index + rgba + 3] = 255;
    }

    const i420 = {
      y: alloc(height * yRowStride),
      u: alloc(chromaHeight * i420UvRowStride),
      v: alloc(chromaHeight * i420UvRowStride),
      width,
      height,
      yRowStride,
      yPixelStride,
      uvRowStride: i420UvRowStride,
      uvPixelStride,
    };
    const i420DefPtr = writeDef(module, i420);
    allocations.push(i420DefPtr);
    call(module, 'yuv420_from_rgba8888', [rgba, i420DefPtr]);

    expectPadding(module, 'i420.y', i420.y, height, yRowStride, width, yPixelStride, 1);
    expectPadding(module, 'i420.u', i420.u, chromaHeight, i420UvRowStride, chromaWidth, uvPixelStride, 1);
    expectPadding(module, 'i420.v', i420.v, chromaHeight, i420UvRowStride, chromaWidth, uvPixelStride, 1);
    for (let row = 0; row < height; row += 1) {
      for (let column = 0; column < width; column += 1) {
        expectByte('i420 Y', module.HEAPU8[i420.y + row * yRowStride + column * yPixelStride], 82, row, column);
      }
    }
    for (let row = 0; row < chromaHeight; row += 1) {
      for (let column = 0; column < chromaWidth; column += 1) {
        const offset = row * i420UvRowStride + column * uvPixelStride;
        expectByte('i420 U', module.HEAPU8[i420.u + offset], 90, row, column);
        expectByte('i420 V', module.HEAPU8[i420.v + offset], 240, row, column);
      }
    }

    const nv = {
      y: alloc(height * yRowStride),
      u: alloc(chromaHeight * nvUvRowStride),
      v: 0,
      width,
      height,
      yRowStride,
      yPixelStride,
      uvRowStride: nvUvRowStride,
      uvPixelStride: 2,
    };
    const nvDefPtr = writeDef(module, nv);
    allocations.push(nvDefPtr);
    call(module, 'nv21_from_rgba8888', [rgba, nvDefPtr]);
    expectPadding(module, 'nv.y', nv.y, height, yRowStride, width, yPixelStride, 1);
    expectPadding(module, 'nv.uv', nv.u, chromaHeight, nvUvRowStride, chromaWidth, 2, 2);
    for (let row = 0; row < chromaHeight; row += 1) {
      for (let column = 0; column < chromaWidth; column += 1) {
        const planar = row * i420UvRowStride + column * uvPixelStride;
        const interleaved = row * nvUvRowStride + column * 2;
        expectByte('direct U', module.HEAPU8[nv.u + interleaved], module.HEAPU8[i420.u + planar], row, column);
        expectByte('direct V', module.HEAPU8[nv.u + interleaved + 1], module.HEAPU8[i420.v + planar], row, column);
      }
    }

    const convertedNv = {
      y: alloc(height * width),
      u: alloc(chromaHeight * chromaWidth * 2),
      v: 0,
      width,
      height,
      yRowStride: width,
      yPixelStride: 1,
      uvRowStride: chromaWidth * 2,
      uvPixelStride: 2,
    };
    const convertedNvDef = writeDef(module, convertedNv);
    allocations.push(convertedNvDef);
    call(module, 'yuv420_i420_to_nv21', [i420DefPtr, convertedNvDef]);
    for (let row = 0; row < height; row += 1) {
      for (let column = 0; column < width; column += 1) {
        expectByte(
          'i420->nv Y',
          module.HEAPU8[convertedNv.y + row * width + column],
          module.HEAPU8[i420.y + row * yRowStride + column * yPixelStride],
          row,
          column,
        );
      }
    }

    const convertedI420 = {
      y: alloc(height * yRowStride),
      u: alloc(chromaHeight * i420UvRowStride),
      v: alloc(chromaHeight * i420UvRowStride),
      width,
      height,
      yRowStride,
      yPixelStride,
      uvRowStride: i420UvRowStride,
      uvPixelStride,
    };
    const convertedI420Def = writeDef(module, convertedI420);
    allocations.push(convertedI420Def);
    call(module, 'nv21_to_i420', [nvDefPtr, convertedI420Def]);
    expectPadding(module, 'converted i420.y', convertedI420.y, height, yRowStride, width, yPixelStride, 1);
    expectPadding(module, 'converted i420.u', convertedI420.u, chromaHeight, i420UvRowStride, chromaWidth, uvPixelStride, 1);
    expectPadding(module, 'converted i420.v', convertedI420.v, chromaHeight, i420UvRowStride, chromaWidth, uvPixelStride, 1);

    const swapped = alloc(chromaHeight * nvUvRowStride);
    call(module, 'nvXX_to_nvYY', [nv.u, swapped, width, height, nvUvRowStride]);
    expectPadding(module, 'swapped uv', swapped, chromaHeight, nvUvRowStride, chromaWidth, 2, 2);
    for (let row = 0; row < chromaHeight; row += 1) {
      for (let column = 0; column < chromaWidth; column += 1) {
        const offset = row * nvUvRowStride + column * 2;
        expectByte('swapped first', module.HEAPU8[swapped + offset], module.HEAPU8[nv.u + offset + 1], row, column);
        expectByte('swapped second', module.HEAPU8[swapped + offset + 1], module.HEAPU8[nv.u + offset], row, column);
      }
    }
  } finally {
    for (const ptr of allocations.reverse()) module._free(ptr);
  }
}

async function main() {
  const wasmPath = path.resolve(__dirname, '../assets/wasm/yuv_ffi.wasm');
  const module = await createYuvFfiModule({wasmBinary: fs.readFileSync(wasmPath)});
  runSize(module, 1, 1);
  runSize(module, 3, 5);
  runSize(module, 127, 255);
  console.log('YUV-05 WASM harness passed: 3 sizes, 5 conversion paths, exact YUV values.');
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
