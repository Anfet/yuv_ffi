#include "yuv.h"

// This translation unit intentionally contains no definitions.
//
// It previously defined freeYUVDef(), which was never declared in any header,
// never listed in ffigen.yaml, and absent from the WASM EXPORTED_FUNCTIONS
// list, so no caller could reach it. Ownership of the struct and its planes
// belongs to Dart: YUVDefClass.dispose() frees y/u/v and the struct itself,
// mirroring the allocation in the same class. Exporting freeYUVDef() would
// therefore have published a second ownership path that frees package:ffi
// allocations from inside the plugin library, across an unnecessary allocator
// boundary.
