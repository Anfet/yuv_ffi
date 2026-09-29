# Отчёты предрелизного цикла 0.4.2

Отчёты исполнителей, интеграционные проверки и ревью, вынесенные из `pre-release-todo.md` 28.09.2026. Решения архитектора и Engineer остались в карточках.

<!-- RA-21 -->
#### Executor Report
Восстановленный seed harness выдал 1188/1188 строк, идентичных сохранённому 0.4.0 oracle. Созданы 22 отдельных файла с данными операций, golden с 1188 случаями и 949 уникальными результатами, проверка покрытия 12 значений `YuvOperation`, синхронизация копий и layout/pack suite на 54 сочетаниях. `flutter test --tags probe`, copy-sync/coverage/layout suite, analyze и Windows `flutter drive` прошли; Windows log подтвердил 1188 случаев. Web target добавлен; локальный запуск требует ChromeDriver на порту 4444, браузерный gate остаётся RA-41.


<!-- RA-21 -->
#### Review and Rework
T1 review rejected the first implementation (rejection count 1): case coverage did not detect a removed case file, record mode did not match the append-only/overwrite contract, and two stale example helper copies remained. Terra corrected these issues in `d6308d9`; negative control removing `...boxCases` failed as expected. Golden/oracle data stayed unchanged.

Final T1 review accepted branch SHA `a0ce963714420588eed5597acbe187912b4926f0`. Full CI run [36525331117](https://github.com/Anfet/yuv_ffi/actions/runs/36525331117) passed all 11 jobs on that exact SHA.


<!-- RA-26 -->
#### Execution Report — Windows diagnostic JIT, 28.09.2026
The canonical Balanced GUID is active; read-only `root\\wmi:BatteryStatus` returned `PowerOnline=True`, `Discharging=False`. Added a 10-minute test timeout because the full 24-case JIT matrix exceeded test's default 30 seconds. Two full unrecorded runs passed all 24 cases and hashes matched 24/24, but per-case median deltas ranged −47.6% to +23.4%; these runs are unstable diagnostics, not Release baseline evidence. Negative controls passed: injected delay produces strict `SLOWER`/FAIL; wrong golden produces `HASH-MISMATCH`/FAIL. No baseline file was written.


<!-- RA-26 -->
#### Execution Report — Windows Release runner, 28.09.2026
Added `example/probe/windows_release_benchmark.dart` and `tool/probe/run_windows_release.ps1`, plus a pure `test/probe/probe_seed.dart` so the shared tight-input scenarios can compile against 0.4.0. The Release app explicitly checks `kReleaseMode`, emits one atomic JSON verdict, and verifies sample hashes after timing; the host checks a clean exact SHA, Balanced/AC, run ID, full 24-scenario matrix and result integrity. Scoped runner tests passed 10/10, analysis and PowerShell parse passed. Dirty-worktree smoke (`-AllowDirtySmoke`) built/launched Windows Release and returned 24 PASS scenarios with nine sample hashes each; `sourceVerified=false`, saved only in `%TEMP%`, so it is not comparison evidence. Next: commit implementation, build same benchmark source against tag 0.4.0 and committed HEAD in separate worktrees, collect stable repeats and archive raw reports.


<!-- RA-26 -->
#### Execution Report — Pixel 3 arm64 profile diagnostic, 28.09.2026
Corrected Pixel preflight passed: awake, display on, keyguard unlocked, thermal status 0. `flutter drive --profile` completed with exit 0 and `All tests passed`; the strict host accepted exactly one `RA26_ANDROID_RESULT` and emitted `RA26_ANDROID_HOST_RESULT PASS`. Run ID `095d9d326eee4afca9fa1aba1f1a8b68`, device `8B1X11QLW`, ABI `arm64-v8a`, SHA `d8d8d481948f483ef7aa53ed939fbf1db0b962c9`, run-set SHA-256 `2f036abd3bd82f76bff576af34351eefade43ede1686769e2e851c99d6557a46`; 24/24 scenarios PASS with nine samples per scenario. This was a dirty-worktree diagnostic (`sourceVerified=false`), so it created no baseline or archived comparison evidence. Release verification remains separate under RA-25.


<!-- RA-26 -->
#### Integration check — 28.09.2026
The shared root/example `layout_pack_test.dart` files were missing the new `probe_seed.dart` import; Terra fixed both imports. `dart format`, staged/unstaged `git diff --check`, scoped probe/reference tests (122 passed), and the full root suite (711 passed, 1 intentional skip) passed. The existing workspace `yuv_ffi.dll` was supplied through the process-local `PATH` (SHA-256 `9c816b9f59ee159573575c2916321693ae035161d99b92274d9fc21a22365f30`); this is not a fresh native build. CMake is absent on this Windows runner, so a CI-style native build cannot be reproduced locally. `tool/bench/` remains untracked and outside the index. RA-14 was accepted after one comment-only correction; candidate commit is now unblocked.


<!-- RA-26 -->
#### Baseline package provenance audit — 28.09.2026
The initial audit found that the runner proved app Git SHA but not the dependency package selected from `example/.dart_tool/package_config.json`; default `pubspec.yaml` points to HEAD. The required baseline app worktree on committed HEAD must resolve `yuv_ffi` to detached tag `0.4.0` through a controlled `pubspec_overrides.yaml`. That gap is addressed by the implementation report below; no comparison is accepted until validation-only positive/negative proof passes in the clean baseline app worktree.


<!-- RA-26 -->
#### Baseline package provenance gate — implementation report, 28.09.2026
The first runner version supported explicit baseline mode and focused contract tests passed 10/10. On candidate `2ef5e15`, a clean worktree validation resolved the baseline app to tag-tree revision `d5d78eb04cf0b276dbc0a1ba869cd7152daab8f9` and rejected an all-zero expected revision. This was insufficient acceptance: ignored `package_config.json` remained on the old package and caused example analyze to fail; T1 review rejected missing independent clean-tag verification, unsafe cleanup, relative-URI handling and source-text-only tests. Local corrections now pin the actual clean `0.4.0` tag, preserve preexisting overrides, restore default HEAD package resolution, resolve relative URIs, and fail on cleanup errors before emitting PASS. Executable PowerShell controls cover valid tag, wrong revision/path, preexisting override, cleanup failure, and default config restoration. Syntax/diff checks and limited provenance smokes pass; the full clean-worktree control suite and T1 re-review remain pending. No benchmark comparison is accepted. Balanced + AC is valid and is not the reason for rejection.


<!-- RA-26 -->
#### T1 review — package provenance gate, 28.09.2026
**REJECT, Rejection Count 1.** The runner compares a caller-supplied package revision rather than independently verifying tag `0.4.0` and its clean worktree; `-AllowDirtySmoke` may discard existing changes through unconditional `git restore`; cleanup errors are suppressed and PASS may be emitted before cleanup; relative `rootUri` handling is fragile; contract tests inspect source strings instead of exercising failure paths. The stale ignored `example/.dart_tool/package_config.json` caused `example-analyze-and-build (3.44.9)` to fail with 82 missing-API errors after baseline validation. Required corrections are now implemented locally: prove exact tag revision and clean tag worktree, preserve pre-existing files, remove override and restore/verify normal HEAD package resolution, fail on cleanup errors, emit PASS only after cleanup, correctly resolve relative `rootUri`, and use executable positive/negative controls. T1 re-review and clean-worktree full control suite remain pending. Benchmark remains stopped pending acceptance; Balanced + AC is valid.


<!-- RA-26 -->
#### RA-25 evidence archive — 28.09.2026
Both Pixel 3 Release gates passed and host evidence is committed under `doc/archive/release-0.4.2/ra25-pixel3/`: README, arm64/armv7 stdout and stderr, and the final arm64 logcat record. APK SHA-256 values: arm64 `6a175d1dd106bf952489d168f6b9c526ffa260f353b1c02359dec54b2911980f`; armv7 `6543c93155847ba951168a3a4adeb5dd34713335d4fe2719244b137150b4e243`. Both reports prove target-only ABI and `libyuv_ffi.so` ZIP contents, installed `primaryCpuAbi`, unique strict `RA25_RESULT`, smoke/probe PASS, and 1188 cases. Independent T1 acceptance remains.


<!-- RA-22 -->
#### Negative Control and Acceptance
The remote negative control [run 36480495893, attempt 2](https://github.com/Anfet/yuv_ffi/actions/runs/36480495893?attempt=2) used bad SHA `f3304a15d2bd350688ba3c791051ed4751d12625`; Linux, macOS, iOS, and Android probe jobs all failed on the intentionally corrupted I420 golden. Windows failed earlier in copy-sync and did not run its native probe; Windows is outside RA-22 DoD. Revert SHA `a17bbf405cfff29da35add375db05c1cdef58de1` passed [run 36481367925](https://github.com/Anfet/yuv_ffi/actions/runs/36481367925), with 1188 probe cases on each required platform. Final branch CI [run 36487815757](https://github.com/Anfet/yuv_ffi/actions/runs/36487815757) passed 11/11 jobs on release SHA `e4376ab4272511c29a7258bdb599bdc8fde50118`. T1 accepted RA-22.


<!-- RA-25 -->
#### Executor Report
Pixel 3 (`8B1X11QLW`, Android 12, `arm64-v8a,armeabi-v7a,armeabi`) подключён через ADB; экран включён, keyguard снят, thermal status 0. Profile app-runtime smoke и native probe завершились `All tests passed`; probe обработал 1188 случаев. Release APK arm64 и armv7 собраны, в каждой APK подтверждена только целевая ABI и `libyuv_ffi.so`; arm64 APK установлена и запущена без ошибок загрузки библиотеки.

Требуемый `flutter drive --release` прекращается до сборки сообщением, что Flutter Driver не поддерживает release mode. Profile-прогон не подтверждает release assertions, а запуск основного example app подтверждает только открытие приложения. Это историческая блокировка, разрешённая решением ниже от 28.09.2026. Полные команды прежних попыток: `doc/archive/release-0.4.2/pixel3-evidence.md`.


<!-- RA-25 -->
#### T1 review — RA-25 release evidence, 28.09.2026
**REJECT, Rejection Count 1.** The script injects `-GitSha` into the APK and compares logcat to that same parameter; it never checks actual checkout `HEAD` or cleanliness. The parser ignores malformed `RA25_RESULT` markers if one valid JSON record exists (reproduced: two markers yielded one runner record). Archive lacks armv7 raw logcat/device record and APK binaries, preventing independent verification. Runner/parser and executable negative-test corrections are now implemented locally by RA-41; focused tests pass 4/4 and PowerShell parses. T1 re-review is pending. Pixel reruns on a clean committed candidate and full per-ABI archive still remain.


<!-- RA-40 -->
#### Local Reproducibility Report — 28.09.2026
Two isolated `emsdk 3.1.74` release builds in ignored `tool/wasm/out/ra40-a` and `ra40-b` matched the committed assets and each other. SHA-256: `yuv_ffi.js` = `DC5E08EE24EC15D1F10F829D2EB71EA0BFC944F50F63CC14E010EC6C853F39D5`; `yuv_ffi.wasm` = `BAD2FC75799FE29FB40FD9866C2D106B3FA13F1929C41F7A219301C8C0F1D08F`. No tracked files changed. Release CI [run 36476080539](https://github.com/Anfet/yuv_ffi/actions/runs/36476080539) passed on SHA `32239178a59f4c6634f5d384bbac3f7d294a2d70`; reviewer GPT-6 Sol (T1) accepted RA-40.

<!-- RA-41 -->
**Local implementation result:** 39 static registrations preserve 41 runtime cases. All three migrated targets passed with exit 0 and `All tests passed` (48.1 s, 48.4 s, 45.8 s). The legacy `deprecated_member_use` infos are suppressed only in the intentionally legacy atomicity target; `flutter analyze integration_test` now reports no issues. The full dynamic gate passed 13/13 locally. Separate `reference_web_conversions_test.dart` passed 119/119 with zero mismatches in 645.1 s; committed WASM asset hashes were unchanged before/after. Integrated Web CI and the 119-case matrix passed on release SHA `e4376ab` in run `36487815757`. Remaining: execute the remote corrupted-WASM negative control and revert it, then obtain T1 review.

<!-- RA-23 (поглощена RA-72) -->
### RA-23 — Windows CI
Историческая карточка; отдельного активного исполнения нет. Требование вынести Windows CI поглощено RA-72 после M1.

В run `36455663081` обнаружилось расхождение copy-sync (ожидалось 29 root-only helper files, найдено 28). Причину устранила RA-51, добавив новый root-only тест в allowlist; исправление принято по T2 review, а все 11 jobs прошли в run `36471185052` на SHA `ea54e0c78cca5e81db4ddc6ebe035214f63850b0`. Поэтому этот старый отказ больше не является текущей блокировкой.

Текущий целевой результат переноса workflow и Windows проверок зафиксирован в карточке [RA-72](../../../tasks/release-0.4.2/RA-72.md); её зависимости RA-70 и RA-80 ещё не закрыты.

---


<!-- RA-41: разбор Web-расхождений (seed) -->
**Исторический результат до исправления seed:** driver/browser подключились; после пересборки assets через emsdk 3.1.74 матрица дала как минимум 20 несовпадений. Т1 установил, что Web генерировал другие входные байты из-за неточной LCG-арифметики dart2js; golden и оракул верны. Этот результат и блокировка из `doc/archive/release-0.4.2/web-probe-evidence.md` сняты исправлением seed, описанным ниже. После исправления ChromeDriver probe прошёл 1188 операций без mismatches; полный dynamic gate 13/13 целей и отдельная 119-case reference matrix (119/119, mismatches 0) также локально зелёные. Ожидаются CI на общем candidate SHA и remote negative control.

#### Architect Decision 28.09.2026 — причина расхождений на Web

**Дефект в генераторе входа пробы, а не в WASM и не в C.** Golden и оракул 0.4.0 остаются верными.

Генератор байтов в `test/probe/probe_support.dart:140` и `test/probe/layout_pack_test.dart:29` — `seed = (seed * 1103515245 + 12345) & 0x7fffffff`. На VM это точная 64-битная арифметика. В dart2js `int` — это IEEE double: `seed * 1103515245` доходит до ~2,4·10¹⁸ > 2⁵³ и теряет младшие биты, а `&` в JS работает с 32-битным усечением. На Web тест получает **другие входные кадры**, поэтому расходятся все случаи, а не только gray: gray просто идёт первым файлом `cases.dart`, и отчёт показывает первые 20.

Проверено архитектором: одна и та же функция скомпилирована в VM и в dart2js (запуск в Node). Последовательность расходится со второго шага (`firstDiff=1`, контрольная сумма 200 000 байт `830980134` на VM и `86505086` в dart2js). Точная web-безопасная замена ниже даёт в dart2js ту же сумму `830980134`, что и VM, то есть совпадает побайтно.

**Что сделать:**
1. В обоих местах заменить шаг генератора на точный эквивалент, у которого все промежуточные значения меньше 2⁵³ и нет побитовых операций над большими числами:
   ```dart
   /// Same sequence as `(s * 1103515245 + 12345) & 0x7fffffff`, computed
   /// exactly on the web too: every intermediate stays below 2^53.
   int probeNextSeed(int s) {
     const aHi = 16838; // 1103515245 ~/ 65536
     const aLo = 20077; // 1103515245 % 65536
     final hi = (s * aHi) % 32768;
     return (s * aLo + hi * 65536 + 12345) % 2147483648;
   }
   ```
   Функция объявляется один раз в `probe_support.dart`; `layout_pack_test.dart` использует её, а не свою копию. `(seed >> 8) & 0xff` менять не нужно: `seed < 2³¹`.
2. Синхронизировать копии в `example/integration_test/helpers/probe/` штатным скриптом копирования.
3. Отчёт о расхождениях: в `expectProbeMismatchesEmpty` выводить общее число расхождений и первые 20, а не только первые 20.
4. Добавить быструю проверку входа, чтобы отличать «другой вход» от «другой результат»: в `golden.json` дописать (режим `PROBE_RECORD=1`, записать на VM) id `input <format> <W>x<H> <layout>` со значением sha16 от `toBytes()` сгенерированного исходного кадра до операции; `probe_correctness_test` и `probe_web_test` проверяют эти id первыми и падают с сообщением «генератор входа расходится на этой платформе».

**Проверка:**
- VM: `flutter test --tags probe` — 0 расхождений с существующим golden (последовательность не меняется, эквивалентность доказана выше) и совпадение с оракулом 0.4.0.
- Web (локально, как в записи выше): 0 расхождений. Если после исправления остаются расхождения — вход уже гарантированно одинаковый, значит это реальное различие WASM и native. Тогда ARCHITECT_REQUIRED с **полным** списком, golden не менять.
- Затем прежний DoD: зелёная CI-джоба и негативный контроль.
