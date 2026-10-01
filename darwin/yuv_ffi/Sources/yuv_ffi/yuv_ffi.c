// Forwards src/yuv_ffi.c so the Apple build compiles it as its own translation unit.
// test/apple_forwarder_sources_test.dart compares this directory with src/CMakeLists.txt.
#include "../../../../src/yuv_ffi.c"
