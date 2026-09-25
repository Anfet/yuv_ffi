# MEAS-03: `flip vertical` — Windows slice

**Статус:** Windows-часть измерена; общий baseline ещё не принят. Для принятия нужны Android и Web slices MEAS-02/03.

**Протокольное замечание:** MEAS-01 требует High performance или Ultimate Performance. Во время этого запуска был активен Balanced, поэтому эти цифры годятся только как диагностические и не готовы к приёмке baseline. Windows slice нужно повторить на разрешённом плане; системный power plan при этом запуске не менялся.

**Воспроизводимость и доступность плана:** повторно проверены Windows runner, input SHA gate и manifests. Текущий `powercfg /list` показывает только Balanced и Power saver, активен Balanced. Оба доступны плана запрещены MEAS-01, поэтому на этой машине сейчас нельзя получить валидный Windows baseline по заданному протоколу. Не переключать план и не считать ранее записанный CSV приемлемым.

## Контракт и артефакты

Измерялись `FLIP.I420.V`, `FLIP.NV12.V`, `FLIP.BGRA.V` на `1920x1080` и `4000x3000`, по три interleaved round, версии `v024` и `abi_v1`. Получено 36 строк: 2 версии × 3 сценария × 2 размера × 3 раунда. Все статусы `OK`.

| Версия | Commit SHA | `src` tree |
|---|---|---|
| v024 | `5f52fd14540a283da91a6d80e1fc7128bba1c796` | `eba076b4cc9a0d7a686b61edbbb8101da9270356` |
| ABI v1 candidate | `35c516e216fef8d5ed4ef379d38655fc643f738d` | `9029ff28d9834c069f41159d122b36ed6d9d4968` |

Обе сборки взяты из имеющихся Windows Dart AOT артефактов в `%TEMP%\yuv_ffi_dart_bench`; скрипт сверил manifests, SHAs, `src` trees, executable paths и хеши benchmark sources. Артефакты не перестраивались. Для обеих версий manifest указывает Flutter 3.44.9, Dart 3.12.2 и engine content hash `b9499e4c25212536ba3a4eec4f5c1905fb3214fe`; flags: `AOT+MSVC-/MD-/O2-/Ob2-/DNDEBUG`.

## Условия Windows

- Machine: `OLEG-WORK`, Alienware m18 R1; Windows 10 Home 10.0.19045, x64.
- CPU: 13th Gen Intel Core i9-13980HX, 24 cores / 32 logical processors; RAM 63.7 GiB.
- Active power plan during measurement: **Balanced**, GUID `381b4222-f694-41f0-9685-ff5bb260df2e`.
- Protocol requirement in [MEAS-01 run instructions](MEAS-01-run-instructions.md): High performance or Ultimate Performance. This run did not meet it; preserve its output as diagnostic evidence only until repeated on an allowed plan.
- Current `powercfg /list` exposes only Balanced (`381b4222-f694-41f0-9685-ff5bb260df2e`) and Power saver (`5083e697-ad0a-4cc5-af6b-19b8d19d6930`). Neither satisfies the protocol. No plan changes were made; this machine cannot produce an accepted Windows baseline under the present requirement.
- Driver affinity: `0x4`; child priority: `HIGH_PRIORITY_CLASS`.
- All results are public Dart AOT calls (`level=dart`, `layout=tight`). The harness records per-process calibration/warmup and raw timed samples in the CSV.
- Round wall-clock intervals (UTC): round 1 `16:23:11.0847313–16:24:12.6054993`, round 2 `16:24:12.6107490–16:25:13.7338328`, round 3 `16:25:13.7350528–16:26:14.4538133`, 2026-09-25.

## Timings

Values are milliseconds. Each round cell is that process's `median_ms`; **center** is the median of the three round medians. Spread is `(max/min - 1)` across those three round medians. Full raw samples and per-process `min_ms`, `p95_or_max_ms`, `mean_ms`, `stdev_ms`, and `spread` remain in the CSV.

| Scenario | Size | Version | Round 1 / 2 / 3 | Center | Range | Spread |
|---|---:|---|---:|---:|---:|---:|
| FLIP.I420.V | 1920x1080 | v024 | 3.8975 / 3.8105 / 3.8645 | 3.8645 | 3.8105–3.8975 | 2.3% |
| FLIP.I420.V | 1920x1080 | abi_v1 | 108.6000 / 110.0490 / 108.6210 | 108.6210 | 108.6000–110.0490 | 1.3% |
| FLIP.NV12.V | 1920x1080 | v024 | 3.7410 / 3.3665 / 3.3185 | 3.3665 | 3.3185–3.7410 | 12.7% |
| FLIP.NV12.V | 1920x1080 | abi_v1 | 94.0475 / 94.2295 / 94.7830 | 94.2295 | 94.0475–94.7830 | 0.8% |
| FLIP.BGRA.V | 1920x1080 | v024 | 8.2935 / 10.1000 / 8.3000 | 8.3000 | 8.2935–10.1000 | 21.8% |
| FLIP.BGRA.V | 1920x1080 | abi_v1 | 87.3600 / 88.4665 / 88.6485 | 88.4665 | 87.3600–88.6485 | 1.5% |
| FLIP.I420.V | 4000x3000 | v024 | 22.3085 / 23.0760 / 22.5960 | 22.5960 | 22.3085–23.0760 | 3.4% |
| FLIP.I420.V | 4000x3000 | abi_v1 | 622.2550 / 629.9970 / 625.4820 | 625.4820 | 622.2550–629.9970 | 1.2% |
| FLIP.NV12.V | 4000x3000 | v024 | 22.3540 / 22.7690 / 22.1495 | 22.3540 | 22.1495–22.7690 | 2.8% |
| FLIP.NV12.V | 4000x3000 | abi_v1 | 560.5370 / 540.9070 / 539.0000 | 540.9070 | 539.0000–560.5370 | 4.0% |
| FLIP.BGRA.V | 4000x3000 | v024 | 58.9075 / 56.5615 / 59.0735 | 58.9075 | 56.5615–59.0735 | 4.4% |
| FLIP.BGRA.V | 4000x3000 | abi_v1 | 500.9220 / 494.0210 / 494.1970 | 494.1970 | 494.0210–500.9220 | 1.4% |

## Output checksums

For each row below the SHA-256 matched between v024 and ABI v1 and remained identical across all three rounds:

| Scenario | Size | Output SHA-256 |
|---|---:|---|
| FLIP.I420.V | 1920x1080 | `3809b84e185696e03885a5f1fc1662eeb313c52d568e12a8712a9015295e1f9b` |
| FLIP.NV12.V | 1920x1080 | `d87350a9d70881ce01da8c36f9948b57ed8eb442888674c11ecdaa80ef678b82` |
| FLIP.BGRA.V | 1920x1080 | `7e3e5c72aa9d1188d0b3e071309d54832cf1fdc84d143603ec80790e1554a9d6` |
| FLIP.I420.V | 4000x3000 | `3f99368f921a5c9e6d563b50faccbccaaed394716e1e4a9359a39a006499424a` |
| FLIP.NV12.V | 4000x3000 | `85dbfd616c298c507d35c8ee4f6f36040210e6a072607ce1eda2998a7bff74e6` |
| FLIP.BGRA.V | 4000x3000 | `c620da3f55264f92daa84f5f6b88e7b763e4a82aa958c5a36579309b46b359a9` |

## Reproduction

Run from the repository root in PowerShell. The example writes to a unique timestamped CSV so it never targets the captured file or an earlier run. The captured raw results are in [`results/meas03_flip_vertical_windows.csv`](results/meas03_flip_vertical_windows.csv). Check `powercfg /getactivescheme` first and run only with High performance or Ultimate Performance; do not use Balanced results as an accepted baseline.

```powershell
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$out = "doc/perf/results/meas03_flip_vertical_windows_$stamp.csv"
if (Test-Path -LiteralPath $out) { throw "Output already exists: $out" }
.\tool\bench\run_dart_windows.ps1 `
    -ExeV024 "$env:TEMP\yuv_ffi_dart_bench\app_v024\build\windows\x64\runner\Release\yuv_bench.exe" `
    -ExeAbiV1 "$env:TEMP\yuv_ffi_dart_bench\app_abi_v1\build\windows\x64\runner\Release\yuv_bench.exe" `
    -ScenarioIds FLIP.I420.V,FLIP.NV12.V,FLIP.BGRA.V `
    -OutCsv $out `
    -ShaAbiV1 35c516e216fef8d5ed4ef379d38655fc643f738d `
    -TreeAbiV1 9029ff28d9834c069f41159d122b36ed6d9d4968 `
    -ShaV024 5f52fd14540a283da91a6d80e1fc7128bba1c796 `
    -TreeV024 eba076b4cc9a0d7a686b61edbbb8101da9270356 `
    -Sizes 1920x1080,4000x3000 `
    -Rounds 1,2,3
```

Validation: manifest gates passed; captured CSV header has 34 columns and the file contains 36 data rows; all 36 statuses are `OK`; every scenario/size/round has one row for each version; all six scenario/size checksum pairs match between versions. The adjacent `.rounds.log` records round intervals. These checks validate the recorded run, but do not resolve its Balanced-plan protocol mismatch.

Independent runner/input review: before each child process, the PowerShell driver verifies executable presence, manifest version/source SHA/`src` tree/executable path, and current hashes of `bench_common.dart`, `bench_images.dart`, and the version-specific benchmark entrypoint. The Dart runner generates the canonical tight I420/NV12/BGRA frame, hashes its packed active planes, and throws before adapter initialization unless it matches the hard-coded expected input SHA. Expected input SHA-256 values from PERF-01 are:

| Input | 1920x1080 | 4000x3000 |
|---|---|---|
| I420 | `71c06f9341e998b2308625dedffb1555a57cacdb4b1479630039dab4febfc0b4` | `282dc210cc232feb071c75483df66bc14373c7c90d1842a8c9136a3778ceb287` |
| NV12 | `c08dec9993df462f7d96eb3e765ab97b2ac69d86f7bf13e60740ce5c3d4ee652` | `cf70f5e6e0ccee46a5615ba49318d698600ec6a569280d4cc881f38be966d0aa` |
| BGRA | `4a107f2e1d3895761980b2c7e5eecc1a587bffc27626b96868c9c94306dc22a9` | `46cc62c75007006f05e66a39eaf8257a90091f9a97617ca16676a043a5d75146` |

The source-level gate and prior successful 36-row run establish reproducibility of runner, pinned builds, input identity, and output checksums. They do not establish timing validity under the missing required power plan. No timing rerun was performed because neither available plan meets MEAS-01.

This Windows slice is diagnostic evidence only because it used Balanced. Repeat it on a machine or environment with High performance or Ultimate Performance available before Windows acceptance. The operation baseline remains pending until that repeat and the matching Android and Web measurements are complete and reviewed.
