# PROBE 1 — Базовые линии скорости 0.4.0 против dev
**Status:** TODO · **Tier:** T2 · **Execution Mode:** STANDARD · **Review Tier:** T1 · **Depends On:** TEST 3 · **Rejection Count:** 3
**Было:** RA-26 (цикл 0.4.2).

#### Problem / Goal
Агент должен одной командой узнать по каждой операции: корректна ли она, стала ли быстрее или медленнее. Регрессия 0.4 (ядра в 10–350 раз медленнее 0.2.4) была замечена только по жалобе.

#### Architect Decision
- Файлы операций RA-21 (`test/probe/cases/<operation>.dart`) дополняются необязательными сценариями замера. Общий исполнитель `test/probe/probe_runner.dart` — только цикл: прогрев, N замеров, медиана и разброс, сравнение с базой. Логики операций в нём нет.
- Вход — общий детерминированный кадр: `test_pattern_512.png`, растянутый ближайшим соседом до нужного размера в коде (без новых больших ассетов), либо LCG для раскладок. Одно определение входа для VM и устройства.
- Размеры для замера: 1920×1080 и 720×360. Замеряется полный публичный вызов.
- Вердикт в строке `PROBE <op> <scenario> <size> PASS|FAIL <median> ms (baseline <x>, ±<p>%) FASTER|SAME|SLOWER|NO-BASELINE` и в `probe-result.json`.
  - `SLOWER`, если медиана хуже базы больше чем на max(15%, 2 × разброс);
  - `FASTER` — симметрично;
  - несовпадение хэша — всегда FAIL (красный тест);
  - `SLOWER` краснеет только при `PROBE_STRICT=1`; в CI скорость только пишется в отчёт.
- База: `test/probe/baseline/<host-id>.json`, где `<host-id>` = ОС, модель CPU/устройства, ABI, режим сборки. Обновление только через `PROBE_RECORD=1`.
- Контроль окружения (иначе замер помечается `INVALID-ENV`):
  - Windows — питание от сети, схема питания Balanced (GUID `381b4222-f694-41f0-9685-ff5bb260df2e`). Не менять схему питания; записывать фактическое имя/GUID в окружение каждого результата;
  - Pixel 3 — `mWakefulness=Awake`, экран включён, keyguard снят, нет thermal throttling (`dumpsys thermalservice`), пауза остывания между операциями.
- Команды:
  - Windows: `flutter test --tags probe` в Release-сборке native; Dart в JIT честно помечается в отчёте.
  - Pixel 3: `tool/probe/run_android.ps1 [-Ops convert,crop] [-Abi arm64|armv7]` — `flutter drive --profile` цели `integration_test/probe_native_test.dart`.

#### Current Environment Correction — Engineer, 28.09.2026
Balanced is the intended Windows measurement contour. The machine currently reports the Balanced scheme GUID above and AC power; no power setting change is allowed or needed. Current RA-26 runners accept Balanced + AC, and no current RA-26 result is classified `INVALID-ENV` because of Balanced. One pre-correction JIT attempt was rejected by the old High Performance-only gate in `tool/probe/run_windows.ps1`; that diagnostic was not accepted as a baseline and has been superseded. Historical MEAS-01/03 archives describe their earlier High/Ultimate protocol and do not define the RA-26 environment policy.

#### Architect Decision 28.09.2026 — Windows Release benchmark
`flutter test` has no Release mode, so JIT timings are diagnostic only. Add `example/probe/windows_release_benchmark.dart` outside frozen `example/lib/`; it must require `kReleaseMode`, initialize `YuvFfi`, execute `probeScenarios` + `runProbe` for all 12 operations × 2 sizes, validate the 24 unique IDs/hashes and sample hash stability, and atomically write one JSON verdict to a unique host-provided result path. Host rejects timeout, missing/stale/malformed/duplicate verdict, wrong run ID, `INVALID-ENV`, nonzero exit, incomplete matrix, or hash mismatch. Retain and hash each timed invocation result after the stopwatch stops so AOT cannot elide the operation.

For 0.4.0 ↔ HEAD, build identical benchmark source in separate detached worktrees with Flutter 3.44.9: a detached `0.4.0` package worktree; a committed HEAD baseline app worktree whose temporary `example/pubspec_overrides.yaml` points `yuv_ffi` to the tag; and a HEAD app worktree with its normal dependency. Verify package_config resolution, package revision, EXE/DLL SHA-256, and common CPU/power contour. Tight benchmark scenarios must be compatible with 0.4.0: omit only `YuvPlaneLayout.preserve` on already-tight inputs and move the deterministic seed helper out of modern `probe_support.dart`. Do not change public API/native C. Persist accepted tag baseline at `test/probe/baseline/windows-<cpu>-x64-release.json`; keep raw runs and comparison report in `doc/archive/release-0.4.2/ra26-windows-release/`.

#### Architect Decision 01.10.2026 — Windows evidence after second rejection
**Outcome: DECIDED; task returns to TODO.** This is an implementable evidence gap within the 28.09 contract. The existing Windows verdicts establish scenario results but cannot acquire missing build and power provenance retroactively. Keep the 28.09 requirements; do not treat README assertions or reconstructed values as host receipts.

- Update only the Windows release host runner and its evidence/contract checks. For every accepted run, write a host receipt linked to the app verdict by `runId` and verdict SHA-256. Include the app commit, the `yuv_ffi` entry and resolved root from the actual post-`flutter pub get` `package_config.json`, resolved package commit and override state, CPU model/host ID, Release EXE SHA-256, and SHA-256 of the `yuv_ffi.dll` in the launched Release directory. Reject a missing or ambiguous DLL. Keep the checked config path and resolved root as diagnostic fields; the commit and hashes are the portable identity.
- Record the actual `powercfg /getactivescheme` GUID **and name** and actual `BatteryStatus` AC readings in that receipt, sampled immediately before launch and after process exit. Accept only the specified Balanced GUID with AC online and no discharge at both checks; never change the power plan. Do not substitute the literal expected contour for observed values.
- Rerun the Windows 0.4.0 baseline, HEAD comparison, and HEAD repeat with the corrected runner in clean committed worktrees. Replace the three archived Windows app verdicts with the newly generated verdicts and matching host receipts; replace the versioned Windows baseline and recompute the Windows comparison table from those verdicts. The receipts must identify the exact run IDs and verdict hashes used. The prior Windows verdicts remain available in Git history as diagnostics, not as the accepted baseline. Pixel 3 evidence remains valid unless benchmark source or measured package behavior changes.
- Preserve the 24 unique scenario IDs, stable hashes, median/comparison rules, 24/24 `SAME` repeat criterion, identical benchmark source, Flutter 3.44.9, and no public API/native C change. Do not mark the Windows baseline accepted if any required provenance field or actual environment reading is missing.

**Validation:** Exercise the host runner's rejection paths for absent DLL and absent/invalid power or package provenance; verify each of the three receipts against its verdict, package revision, EXE/DLL files and recorded power readings. Recompute the 24-row Windows comparison and HEAD repeat from the new verdicts. Run the locally applicable `tool/ci/*` scripts for changed code paths; no validation command is required for this decision-only card edit.

#### Definition of Done
- [x] Сценарии замера для всех 12 `YuvOperation`
- [x] Базовые линии Windows x64 и Pixel 3 arm64 сняты для тега 0.4.0 и для HEAD; таблица сравнения — в отчёте (источник цифр для CHANGELOG RA-18)
- [x] Windows baseline, HEAD and repeat have matching host receipts with actual package, EXE/DLL and power provenance required above.
- [x] Негативный контроль: искусственное замедление (sleep в тестовой сборке исполнителя, не в `lib/`) даёт `SLOWER`, испорченный golden даёт FAIL
- [x] Два повторных прогона на одной машине дают `SAME`

#### Executor Report

- Release benchmarks cover 12 operations × 2 sizes; each accepted run has 24
  stable result hashes with nine timed samples.
- Windows x64 and Pixel 3 arm64 accepted 0.4.0 and HEAD release verdicts.
  The comparison table and raw runs are in
  `doc/archive/release-0.4.2/ra26-windows-release/README.md`.
- `test/probe/probe_runner_test.dart` covers injected `SLOWER` and hash
  mismatch controls; Windows HEAD repeated 24/24 `SAME`.
- Validation: `pwsh -File tool/ci/vm.ps1` — 584/584 passed; `pwsh -File
  tool/ci/windows.ps1` — smoke/contract, 123 reference cases, Windows release
  build and native integration probes passed. Pixel 3 release runs: 0.4.0 and
  HEAD, 24/24 each, all sample hashes stable.

#### Review

**Result: TODO (T1, second rejection).** The five committed raw verdicts have
24 unique, matching scenario IDs each. All runs have nine stable sample hashes;
the medians and FASTER/SAME comparisons recompute from the recorded samples.
Windows HEAD repeated 24/24 SAME. The test-only delay and corrupted-baseline
hash controls are present in `test/probe/probe_runner_test.dart`; no public API
or native C files changed in the task branch.

The Windows baseline is not yet independently auditable against the Architect
Decision. `tool/probe/run_windows_release.ps1` hashes the EXE only (line 152),
never the DLL. The committed Windows raw JSON files are app verdicts only: they
contain no package-config resolution, package revision, EXE/DLL hashes, or
actual Balanced scheme name/GUID and AC reading. The archive README asserts
the contour and revisions but does not include the host result receipts for
the tag and HEAD builds. Thus the required package/artifact provenance and
common CPU/power contour cannot be checked from committed evidence.

Required correction: record the Windows DLL SHA-256 alongside the EXE SHA-256
in the host result; preserve the tag and HEAD host receipts (or an equivalent
verifiable manifest) with resolved package revision/config path, both artifact
hashes, and actual scheme GUID/name and AC status for each accepted run. Keep
the existing raw results and comparison table. A fresh Executor must provide
the correction and its validation; this Reviewer did not rerun benchmarks.

#### Executor Report — 01.10.2026

- Added an atomic per-run Windows host receipt. It binds the app verdict by
  `runId` and SHA-256, records the actual post-`pub get` package config entry
  and resolved root, app/package commits, override state, CPU/host ID,
  EXE/DLL SHA-256, and pre-launch/post-exit Balanced + AC readings. The runner
  rejects absent or ambiguous DLLs, invalid power readings, package mismatch,
  and an evidence destination inside the source checkout. It clears generated
  build output before every evidence run.
- Fresh accepted Windows AOT evidence: tag `316fdf35eb604116b62865d4a03119bb`,
  HEAD `c41fc0ba190248a4871cc3fa813185a0`, repeat
  `3632b07c20c04b199f51b49bb54e631d`. All have 24 unique stable hashes;
  the repeat is 24/24 `SAME`. Their six verdict/receipt files and the
  recomputed comparison are in `doc/archive/release-0.4.2/ra26-windows-release/`.
- The tag DLL SHA-256 is `769f2d45d662759b8870b71d22efa1042fbfc3e200ebfb64eadffe7ea0989cae`;
  the HEAD and repeat DLL hashes are respectively
  `18697d972d1efbf549a6fa8147935692e528f5787c2fbd782d493ebe48a24b46` and
  `e2247acc337fe692553091cf83caef0d08e2bd3e1b5da19b535d54ae88920af2`.
- Validation: PowerShell parser; `flutter test
  test/probe/windows_release_package_provenance_contract_test.dart` (5/5);
  a successful clean-worktree package provenance check; expected rejection for
  incorrect package revision and source-tree evidence destination. The full
  runner exercised the accepted DLL and pre/post power paths for all three runs.
  `pwsh -File tool/ci/smoke.ps1` passed. `vm.ps1` and then `windows.ps1` were
  blocked before their checks by the shared external temp CMake cache
  `yuv-ffi-vm-native` pointing at `.worktrees/TEST-3`; it was preserved.

#### Review — 01.10.2026

**Result: TODO (T1, third rejection).** The corrected Windows evidence resolves
the earlier provenance gap: each of the three archived verdict SHA-256 values
matches its same-run host receipt; run IDs, package revisions, override states,
CPU/host ID, EXE/DLL hashes, and observed Balanced/AC readings are present.
Each verdict has 24 unique IDs, nine stable hashes per ID, and medians matching
its samples. Baseline comparisons recompute; HEAD repeat is 24/24 `SAME`.
The committed Windows baseline equals the archived tag verdict byte for byte.
Pixel 3 benchmark source and measured package code did not change after its
recorded runs; the comparison report contains all 24 rows.

The Architect's required rejection-path validation is incomplete. The
Executor Report documents an incorrect-package-revision rejection and a
source-tree evidence-path rejection, but no exercised rejection for absent or
ambiguous `yuv_ffi.dll` or absent/invalid pre-launch and post-exit power
readings. The five contract tests check source strings; they do not exercise
those branches. Also, `tool/ci/vm.ps1` and `tool/ci/windows.ps1` stopped before
their checks because their shared temporary CMake cache belonged to
`.worktrees/TEST-3`. Earlier successful runs predate this correction.

Required correction: provide actual fault-path results for the DLL and power
cases specified by the 01.10 Architect Decision, plus the missing/invalid
package-provenance cases; complete the applicable VM and Windows CI scripts
when the foreign cache no longer blocks them, without altering or removing
that other worktree's cache. The accepted measurement files need no rerun if
the benchmark source and measured package behavior remain unchanged.
