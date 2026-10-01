// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "yuv_ffi",
    platforms: [
        .iOS("13.0"),
        .macOS("10.15"),
    ],
    products: [
        // Dynamic on purpose: Dart resolves the yuv_*_v1 symbols through
        // DynamicLibrary.process(), and nothing in Swift/ObjC references these
        // C functions. A static library would let the linker drop every
        // object file, so the symbols would be missing at runtime.
        .library(name: "yuv-ffi", type: .dynamic, targets: ["yuv_ffi"]),
    ],
    targets: [
        .target(name: "yuv_ffi"),
    ]
)
