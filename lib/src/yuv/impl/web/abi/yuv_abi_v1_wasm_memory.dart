// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:typed_data';

import 'package:yuv_ffi/src/web/impl/js_util_compat_web.dart' as js_util;

/// A scoped `_malloc`/`_free` arena over a WASM module's linear memory
/// (YUV-51).
///
/// This is the Web counterpart of `NativeAllocator` on the IO side: the ABI v1
/// Web runner stages every descriptor, options struct and plane buffer through
/// one of these, and [freeAll] releases them in a single `finally`, so a throw
/// partway through staging cannot leak WASM memory.
///
/// Allocations are tracked in reverse order and freed reverse-to-allocation,
/// mirroring the IO runner's "dispose options, destination, and source" order.
/// A pointer freed here is never referenced again: the runner copies every
/// result byte into a Dart-owned buffer before the arena is released.
class WasmArena {
  /// Creates an arena allocating from [module]'s `_malloc`.
  WasmArena(this.module);

  /// The Emscripten module this allocates from.
  final Object module;

  final List<int> _pointers = <int>[];

  /// Allocates [size] zero-filled bytes and returns the pointer.
  ///
  /// Emscripten's `_malloc` does not zero its result, but every ABI v1
  /// descriptor has reserved fields that must read as zero, so this zeroes the
  /// block explicitly rather than relying on a fresh heap. That makes it the
  /// behavioural equal of the IO side's `calloc`, which the runner's contract
  /// depends on for both reserved fields and unused plane slots.
  int allocateZeroed(int size) {
    if (size <= 0) {
      // A zero-length allocation still has to yield a distinct, freeable
      // pointer: the descriptor stores it and `freeAll` frees it. Rounding up
      // to one byte keeps `_malloc(0)`'s implementation-defined result out of
      // the contract.
      size = 1;
    }
    final ptr = js_util.callMethod<num>(module, '_malloc', <Object>[size]).toInt();
    if (ptr == 0) {
      throw StateError('WASM allocation failed for $size bytes.');
    }
    _pointers.add(ptr);
    heapU8().fillRange(ptr, ptr + size, 0);
    return ptr;
  }

  /// Allocates [bytes.length] bytes and copies [bytes] into them.
  int allocateBytes(Uint8List bytes) {
    final ptr = allocateZeroed(bytes.length);
    if (bytes.isNotEmpty) {
      heapU8().setRange(ptr, ptr + bytes.length, bytes);
    }
    return ptr;
  }

  /// Frees every pointer this arena handed out, in reverse allocation order.
  ///
  /// Safe to call once after a partially completed staging sequence: only
  /// pointers `_malloc` actually returned were recorded.
  void freeAll() {
    for (int i = _pointers.length - 1; i >= 0; i--) {
      js_util.callMethod<void>(module, '_free', <Object>[_pointers[i]]);
    }
    _pointers.clear();
  }

  /// A fresh view over the module's `HEAPU8`.
  ///
  /// Deliberately re-read on every access rather than cached: the module is
  /// built with `ALLOW_MEMORY_GROWTH`, and a growth detaches the previous
  /// `ArrayBuffer`, leaving any retained view throwing on use. Every read and
  /// write here therefore goes through a view taken after the last possible
  /// allocation.
  Uint8List heapU8() {
    final heap = js_util.getProperty<Object>(module, 'HEAPU8');
    final buffer = js_util.getProperty<ByteBuffer>(heap, 'buffer');
    final length = js_util.getProperty<num>(heap, 'length').toInt();
    return Uint8List.view(buffer, 0, length);
  }

  /// Reads [length] bytes at [ptr] into a Dart-owned buffer.
  Uint8List read(int ptr, int length) {
    final out = Uint8List(length);
    if (length > 0) {
      out.setRange(0, length, heapU8(), ptr);
    }
    return out;
  }

  /// Writes a little-endian `uint32` at byte offset [ptr] + [offset].
  void writeUint32(int ptr, int offset, int value) => _byteData().setUint32(ptr + offset, value, Endian.little);

  /// Writes a little-endian `int32` at byte offset [ptr] + [offset].
  void writeInt32(int ptr, int offset, int value) => _byteData().setInt32(ptr + offset, value, Endian.little);

  /// Writes a little-endian `uint64` at byte offset [ptr] + [offset].
  ///
  /// wasm32 is little-endian and Dart's web `int` is a JS double, so a value
  /// beyond 2^53 could not be represented here in the first place. Every
  /// `uint64` ABI v1 defines is a length or a row stride, which are bounded by
  /// the heap size, so the write is split into two 32-bit halves rather than
  /// using `setUint64` -- which `dart2js` does not support at all.
  void writeUint64(int ptr, int offset, int value) {
    final data = _byteData();
    data.setUint32(ptr + offset, value & 0xFFFFFFFF, Endian.little);
    data.setUint32(ptr + offset + 4, value ~/ 0x100000000, Endian.little);
  }

  /// Writes a little-endian IEEE-754 `double` at byte offset [ptr] + [offset].
  void writeFloat64(int ptr, int offset, double value) => _byteData().setFloat64(ptr + offset, value, Endian.little);

  /// Writes a wasm32 pointer (a 32-bit address) at byte offset
  /// [ptr] + [offset].
  ///
  /// Named apart from [writeUint32] because it marks the one member whose
  /// width legitimately differs between wasm32 and native64 -- the plane
  /// descriptors' `data` -- which is exactly what the C header's
  /// `sizeof(void *)` assertion is about.
  void writePointer(int ptr, int offset, int address) => writeUint32(ptr, offset, address);

  ByteData _byteData() {
    final view = heapU8();
    return ByteData.view(view.buffer, view.offsetInBytes, view.lengthInBytes);
  }
}
