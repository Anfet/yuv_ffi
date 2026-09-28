# Web probe evidence

Date: 2026-09-28
Runner: Windows x64 `dev.working`
Browser: Chrome 154.0.8037.58 with ChromeDriver 154.0.8037.57
WASM toolchain: Emscripten 3.1.74 (`1092ec30a3fb1d46b1782ff1b4db5094d3d06ae5`)

## Rebuild

Ran `sh ./tool/wasm/build_wasm.sh --profile release` after loading the isolated emsdk at `D:\.projects\.tools\emsdk-3.1.74`. The build completed and produced both package assets. A second build completed with no further asset diff, confirming deterministic output on this runner.

## Browser probe

From `example/`, ran:

```powershell
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/probe_web_test.dart -d web-server --browser-name=chrome --headless
```

ChromeDriver connected and the probe failed with exit code 1 in `Web operation matrix matches the exact golden`. Mismatches are for gray operations in I420 and NV12 across tight, padded, and gap layouts. The diagnostic helper reports only its first 20 mismatches (`mismatches.take(20)`), so this is a lower bound, not a complete count. Reported cases:

```text
i420 1x1 tight gray
i420 1x1 padded gray
i420 1x1 gap gray
i420 2x2 tight gray
i420 2x2 padded gray
i420 2x2 gap gray
i420 3x5 tight gray
i420 3x5 padded gray
i420 3x5 gap gray
i420 16x9 tight gray
i420 16x9 padded gray
i420 16x9 gap gray
i420 33x17 tight gray
i420 33x17 padded gray
i420 33x17 gap gray
i420 127x255 tight gray
i420 127x255 padded gray
i420 127x255 gap gray
nv12 1x1 tight gray
nv12 1x1 padded gray
```

Do not update the golden or change native C based on this evidence alone. RA-41 needs an Architect decision on the expected gray conversion result before proceeding.
