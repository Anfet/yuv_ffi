/// The `YuvStatus` values of the versioned native ABI v1
/// (`docs/api-abi-0.3-design.md` section 9) and their Dart exception mapping
/// (`doc/api-abi-0.4-design.md` section 2, contract 6, and section 7's
/// [YuvNativeException] definition).
///
/// This maps a single [int] returned by a `yuv_*_v1` symbol to the exception
/// the typed IO/Web runners throw. It does not decide *when* a status is
/// produced — that is entirely native validation — only what each numeric
/// value means to a Dart caller.
library;

import 'package:yuv_ffi/src/yuv/shared/yuv_operation.dart';

/// Marker for a `YuvStatus` value not defined by ABI v1.
///
/// Any status outside `0..7` reaches Dart only if a future native build
/// speaks a newer ABI version than this package understands. The numeric
/// code is preserved in [YuvNativeException.statusCode] rather than being
/// collapsed into a generic failure, so a caller (or a bug report) can still
/// see exactly what the native side reported.
const int yuvStatusUnknownLowerBound = 8;

/// `YUV_STATUS_OK` (0): the operation completed and the destination may be
/// committed.
const int yuvStatusOk = 0;

/// `YUV_STATUS_INVALID_ARGUMENT` (1): a null pointer, a bad ABI version, a
/// `structSize` smaller than the full v1 type, a non-zero reserved field, or
/// an unknown numeric format/matrix/range value. The descriptor itself is
/// malformed.
const int yuvStatusInvalidArgument = 1;

/// `YUV_STATUS_UNSUPPORTED_FORMAT` (2): a known format used in a
/// source/destination pairing (or plane role) an operation does not accept.
const int yuvStatusUnsupportedFormat = 2;

/// `YUV_STATUS_UNSUPPORTED_LAYOUT` (3): a structurally valid layout ABI v1
/// does not implement.
///
/// No `yuv_*_v1` entry point can currently return this value — see the
/// Engineer's YUV-36b decision recorded in `todo.md`: every layout ABI v1
/// defines is either accepted or rejected by a more specific status, so the
/// set this status describes is empty in this ABI version. The mapping below
/// still exists, because a future ABI revision may introduce a layout this
/// build genuinely cannot support, and Dart must already know how to react
/// to it without a follow-up release.
const int yuvStatusUnsupportedLayout = 3;

/// `YUV_STATUS_OVERFLOW` (4): geometry, stride, or span arithmetic could not
/// be carried out on this target without wrapping.
const int yuvStatusOverflow = 4;

/// `YUV_STATUS_ALLOCATION_FAILED` (5): the native side could not allocate
/// scratch memory it needed before writing.
const int yuvStatusAllocationFailed = 5;

/// `YUV_STATUS_INTERNAL_ERROR` (6): an operation-internal failure that is
/// neither a caller mistake nor a resource exhaustion.
///
/// This used to be the placeholder every ABI v1 kernel returned while only
/// validation was implemented (YUV-36b). Those stubs are gone
/// (YUV-22/23/31/32), so a [YuvNativeException] with this code now means a
/// genuine internal defect rather than "kernel pending".
const int yuvStatusInternalError = 6;

/// `YUV_STATUS_UNSUPPORTED_COLOR` (7): a known format declaring a
/// `colorMatrix`/`colorRange` pairing ABI v1 does not support for it.
const int yuvStatusUnsupportedColor = 7;

/// Thrown for a native status that maps to neither [ArgumentError] nor
/// [UnsupportedError]: `4 OVERFLOW`, `5 ALLOCATION_FAILED`, `6 INTERNAL_ERROR`,
/// and any status value ABI v1 does not define
/// (`doc/api-abi-0.4-design.md` section 2, contract 6).
///
/// [statusCode] retains the raw `YuvStatus` value exactly as the native call
/// returned it, including an unknown code -- see section 11: "any unknown
/// non-zero value" still becomes a [YuvNativeException], not a silently
/// dropped failure. [operation] names the public [YuvOperation] that was being
/// attempted, so a caught exception is actionable without a native stack
/// trace; [message] additionally names the `yuv_*_v1` symbol that returned
/// [statusCode], for diagnostics that need the exact native entry point.
class YuvNativeException implements Exception {
  /// Creates an exception for [statusCode] returned while attempting
  /// [operation]. [message] must be non-empty.
  const YuvNativeException({required this.statusCode, required this.operation, required this.message})
    : assert(message != '', 'YuvNativeException.message must be non-empty.');

  /// The raw `YuvStatus` value the native call returned.
  final int statusCode;

  /// The public [YuvOperation] that was being attempted when the native call
  /// returned [statusCode].
  final YuvOperation operation;

  /// A human-readable description of the failure, non-empty.
  final String message;

  @override
  String toString() => 'YuvNativeException(${operation.name} returned status $statusCode: $message)';
}

/// Translates a raw native `YuvStatus` [status] returned by [nativeSymbol]
/// while attempting [operation] into the Dart result section 11 requires.
///
/// Returns `null` for `YUV_STATUS_OK` (0): the caller commits the destination
/// and does not throw. Every other value throws before returning, per the
/// "Status-to-Dart exception mapping" table:
///
/// | status | Dart result |
/// |---:|---|
/// | 1 | [ArgumentError] naming [nativeSymbol] and the violated contract |
/// | 2, 3, 7 | [UnsupportedError] |
/// | 4, 5, 6, unknown | [YuvNativeException] naming [operation], retaining [status] |
///
/// [detail] is folded into the thrown message where the mapping provides one;
/// it should describe the specific descriptor/options contract the caller can
/// identify without native source, e.g.
/// `'destination geometry does not match crop options'`.
Never yuvThrowForStatus({required int status, required YuvOperation operation, required String nativeSymbol, String? detail}) {
  assert(status != yuvStatusOk, 'yuvThrowForStatus must not be called for YUV_STATUS_OK; the runner commits instead.');

  switch (status) {
    case yuvStatusInvalidArgument:
      throw ArgumentError(detail == null ? '$nativeSymbol: invalid descriptor or options' : '$nativeSymbol: $detail');
    case yuvStatusUnsupportedFormat:
      throw UnsupportedError(detail == null ? '$nativeSymbol: unsupported source/destination format' : '$nativeSymbol: $detail');
    case yuvStatusUnsupportedLayout:
      throw UnsupportedError(detail == null ? '$nativeSymbol: unsupported but structurally valid layout' : '$nativeSymbol: $detail');
    case yuvStatusUnsupportedColor:
      throw UnsupportedError(detail == null ? '$nativeSymbol: unsupported color matrix/range' : '$nativeSymbol: $detail');
    case yuvStatusOverflow:
    case yuvStatusAllocationFailed:
    case yuvStatusInternalError:
      throw YuvNativeException(statusCode: status, operation: operation, message: '$nativeSymbol returned status $status');
    default:
      // Any value ABI v1 does not define. Preserved rather than collapsed --
      // see the class dartdoc.
      throw YuvNativeException(statusCode: status, operation: operation, message: '$nativeSymbol returned unrecognized status $status');
  }
}
