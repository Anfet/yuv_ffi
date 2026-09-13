import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Indirection over raw `calloc` used by the native backend.
///
/// Production code always uses [NativeAllocator.instance], which forwards to
/// `calloc`. Tests may swap in a counting/failing implementation to verify that
/// every successful allocation is released even when a later allocation in the
/// same method throws.
abstract class NativeAllocator {
  /// Allocator used by the native backend.
  static NativeAllocator instance = const CallocNativeAllocator();

  /// Allocates [byteCount] zeroed bytes.
  Pointer<T> allocate<T extends NativeType>(int byteCount);

  /// Releases a pointer previously returned by [allocate].
  void free(Pointer<NativeType> pointer);
}

/// Default [NativeAllocator] backed by `package:ffi` `calloc`.
class CallocNativeAllocator implements NativeAllocator {
  /// Creates the default allocator.
  const CallocNativeAllocator();

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount) => calloc.allocate<T>(byteCount);

  @override
  void free(Pointer<NativeType> pointer) => calloc.free(pointer);
}

/// Test-only allocator that counts outstanding allocations and can fail on
/// demand, so leak paths can be exercised deterministically.
@visibleForTesting
class InstrumentedNativeAllocator implements NativeAllocator {
  /// Creates an allocator that throws on allocation number [failAtAllocation]
  /// (1-based). A `null` value never fails.
  InstrumentedNativeAllocator({this.failAtAllocation});

  /// 1-based index of the allocation that must throw, or `null` to never throw.
  final int? failAtAllocation;

  final Set<int> _live = <int>{};

  /// Number of successful [allocate] calls so far.
  int allocationCount = 0;

  /// Number of allocations that have not been freed yet.
  int get outstanding => _live.length;

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount) {
    allocationCount++;
    if (allocationCount == failAtAllocation) {
      throw _InjectedAllocationFailure(allocationCount);
    }
    final pointer = calloc.allocate<T>(byteCount);
    _live.add(pointer.address);
    return pointer;
  }

  @override
  void free(Pointer<NativeType> pointer) {
    if (!_live.remove(pointer.address)) {
      throw StateError('Double free or free of untracked pointer at ${pointer.address}.');
    }
    calloc.free(pointer);
  }

  /// Frees anything still outstanding so a failing test cannot leak.
  void releaseAll() {
    for (final address in _live.toList()) {
      calloc.free(Pointer<Uint8>.fromAddress(address));
    }
    _live.clear();
  }
}

class _InjectedAllocationFailure implements Exception {
  _InjectedAllocationFailure(this.allocationIndex);

  final int allocationIndex;

  @override
  String toString() => 'Injected allocation failure at allocation #$allocationIndex';
}

/// Runs [body] with [allocator] installed, restoring the previous allocator.
@visibleForTesting
T withNativeAllocator<T>(NativeAllocator allocator, T Function() body) {
  final previous = NativeAllocator.instance;
  NativeAllocator.instance = allocator;
  try {
    return body();
  } finally {
    NativeAllocator.instance = previous;
  }
}
