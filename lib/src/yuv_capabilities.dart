import 'package:yuv_ffi/src/yuv/shared/yuv_operation.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_pixel_format.dart';

/// Immutable snapshot of which public operations the currently loaded backend
/// actually supports (`doc/api-abi-0.4-design.md` section 7).
///
/// A capability answers whether dispatch exists for an operation and format
/// pair, not whether arbitrary input to that operation is valid: invalid
/// geometry still throws [ArgumentError] regardless of what [supports]
/// reports. Returned by [YuvFfi.initialize] once initialization succeeds, and
/// computed once per initialization, never mutated afterwards.
abstract interface class YuvCapabilities {
  /// Whether [operation] is supported for [sourceFormat] and, for
  /// [YuvOperation.convert] only, [destinationFormat].
  ///
  /// [destinationFormat] is required for [YuvOperation.convert] and must be
  /// omitted for every other operation. An unsupported or malformed query --
  /// including a missing/present [destinationFormat] where the operation
  /// requires the opposite -- returns `false` rather than throwing.
  bool supports(YuvOperation operation, {required YuvPixelFormat sourceFormat, YuvPixelFormat? destinationFormat});
}

/// The concrete, unmodifiable [YuvCapabilities] both backends build once
/// initialization succeeds.
///
/// [availableOperations] names exactly the operations whose required ABI v1
/// export actually resolved -- a real dynamic-library symbol on IO
/// (`dlsym`/`providesSymbol`), a real WASM export on Web -- never a hardcoded
/// "everything is supported" assumption. [supports] then narrows an available
/// operation further by the format-pair matrix in
/// `doc/api-abi-0.4-design.md` section 11.
final class YuvCapabilitiesSnapshot implements YuvCapabilities {
  /// Creates a snapshot naming exactly [availableOperations] as backed by a
  /// resolved export. The set is defensively copied and frozen, so a caller
  /// mutating the collection it passed in cannot change this snapshot
  /// afterwards.
  YuvCapabilitiesSnapshot(Iterable<YuvOperation> availableOperations) : availableOperations = Set.unmodifiable(availableOperations);

  /// Every operation whose required ABI v1 export resolved on this backend.
  ///
  /// Membership here means only that dispatch exists; [supports] still
  /// applies the format-pair matrix on top of it.
  final Set<YuvOperation> availableOperations;

  @override
  bool supports(YuvOperation operation, {required YuvPixelFormat sourceFormat, YuvPixelFormat? destinationFormat}) {
    if (!availableOperations.contains(operation)) {
      return false;
    }
    if (operation == YuvOperation.convert) {
      if (destinationFormat == null) {
        return false;
      }
    } else if (destinationFormat != null) {
      // Section 7: destinationFormat "must be omitted for all other
      // operations". Supplying one for a same-format operation is a malformed
      // query, which returns false rather than throwing.
      return false;
    }
    return yuvAbiV1FormatPairSupported(operation, sourceFormat: sourceFormat, destinationFormat: destinationFormat);
  }
}

/// Throws [UnsupportedError] naming [operation] and the formats involved when
/// [capabilities] does not support it, before any allocation, native
/// invocation, or revision change (section 7: "Calling one whose exact
/// format/pair capability is false throws `UnsupportedError` before
/// allocation, native invocation, or revision change.").
///
/// Callers that dispatch an operation against a backend should call this
/// first and let it throw rather than proceeding into backend-specific
/// staging: a rejection here is unconditional and happens before any state
/// this package owns could change.
void yuvRequireCapability(
  YuvCapabilities capabilities,
  YuvOperation operation, {
  required YuvPixelFormat sourceFormat,
  YuvPixelFormat? destinationFormat,
}) {
  if (capabilities.supports(operation, sourceFormat: sourceFormat, destinationFormat: destinationFormat)) {
    return;
  }
  final String formats = destinationFormat == null ? 'source format $sourceFormat' : 'source format $sourceFormat to $destinationFormat';
  throw UnsupportedError('$operation is not supported for $formats on this backend.');
}
