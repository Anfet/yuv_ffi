# RA-25 — Pixel 3 Release Evidence

- Candidate: `1ef71b68540c7133f2e223cd0320b2cb155ecbd5`
- Device: Pixel 3, serial `8B1X11QLW`, Android 12
- Preconditions: awake screen, unlocked keyguard, thermal check passed before each host run.

## arm64-v8a

Command:

```powershell
.\tool\probe\run_release_android.ps1 -GitSha 1ef71b68540c7133f2e223cd0320b2cb155ecbd5 -Abi arm64 -TimeoutSeconds 420
```

- Run ID: `91308400c2904ccfb30828b08bc67e91`
- APK: `app-arm64-v8a-release.apk`
- APK SHA-256: `6a175d1dd106bf952489d168f6b9c526ffa260f353b1c02359dec54b2911980f`
- Host verdict: smoke PASS, probe PASS, 1188 cases.

## armeabi-v7a

Command:

```powershell
.\tool\probe\run_release_android.ps1 -GitSha 1ef71b68540c7133f2e223cd0320b2cb155ecbd5 -Abi armv7 -TimeoutSeconds 420
```

- Run ID: `f78dfc5bf1c3437293a510a9cfa3902e`
- APK: `app-armeabi-v7a-release.apk`
- APK SHA-256: `6543c93155847ba951168a3a4adeb5dd34713335d4fe2719244b137150b4e243`
- Host verdict: smoke PASS, probe PASS, 1188 cases.

For each ABI, `run_release_android.ps1` accepted the run only after it verified exactly one ABI directory in the APK, `lib/<ABI>/libyuv_ffi.so`, installed `primaryCpuAbi`, and exactly one valid `RA25_RESULT` JSON record. The script emits the stored `RA25_HOST_RESULT` only after those checks. APK binaries are deliberately excluded.

## Raw logs

`raw/arm64.stdout.log` and `raw/armv7.stdout.log` contain the strict host results. Matching stderr files are empty. `raw/arm64.logcat-result.txt` contains the one retained device JSON record from the final arm64 run; each run clears logcat before launch.
