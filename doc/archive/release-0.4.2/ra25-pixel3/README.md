# RA-25 — Pixel 3 release evidence

## Accepted result set

- Source checkout: `43835b542bddc16ed5edbd373dbb86ff02c35ac8`
- Device: Pixel 3, serial `8B1X11QLW`, Android 12
- Preconditions: ADB/RSA connected, awake, screen ON, keyguard unlocked,
  thermal status 0.
- Canonical full evidence: the four `ra25-*-{host,device}.json` files in this
  directory. Each host record binds `gitSha` and `revision` to the source
  checkout; its paired device record retains the exact accepted marker.

| ABI | Run ID | APK SHA-256 | Required ZIP entry | Device verdict |
| --- | --- | --- | --- | --- |
| `arm64-v8a` | `43835b542bddc16ed5edbd373dbb86ff` | `3ccb760bb5bf853b9555440161b200d34c9a1de24718a0580972afe3d6ca11e2` | `lib/arm64-v8a/libyuv_ffi.so` | one `RA25_RESULT`, smoke/probe PASS, 1188 |
| `armeabi-v7a` | `f7db33e2a5d64339a86ec5dc53ef0f9a` | `360d95584506955eb4822418e6aa874c41fdfc5bde3ce0550202242c1c3207c5` | `lib/armeabi-v7a/libyuv_ffi.so` | one `RA25_RESULT`, smoke/probe PASS, 1188 |

The host evidence confirms one native ABI per APK and the required
`libyuv_ffi.so`; the device evidence retains the strict marker. The runner
checks `primaryCpuAbi`; its per-ABI results are recorded in the Executor
Report in the RA-25 card. APK binaries are deliberately excluded.

## Raw markers

- `raw/arm64.logcat-result.txt` is the exact accepted arm64 device marker.
- `raw/armv7.logcat-result.txt` is the exact accepted armv7 device marker.

They match the paired device JSON files above. The JSON records are the full
host/device evidence, including APK hash, ZIP entries, device details and
marker payload.

## Historical unbound material

`raw/historical-unbound/` preserves the prior files for
`1ef71b68540c7133f2e223cd0320b2cb155ecbd5`. That runner did not bind its
caller-supplied SHA to checkout HEAD. These files are withdrawn from the
accepted result set and must not be used as source-attributed RA-25 evidence.
