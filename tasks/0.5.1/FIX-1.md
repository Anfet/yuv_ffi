# FIX 1 — README: точный статус Web и платформ, версия 0.5.1
**Status:** IN_PROGRESS · **Tier:** T3, Reviewer T2 · **Owner:** Executor · **Depends On:** — · **Probe:** windows+pixel3 (`src/CMakeLists.txt` — только номер версии; проба — общая для пула `WASM`)

**Base SHA:** `6986feb295e4b1ebbdc2139313044282d5b0daa5` (`dev` на старте пула `WASM`)

#### Goal

Опубликованный README 0.5.0 занижает поддержку Web: раздел «Web backend» пишет «work in progress» и «not
feature-complete with native backends», строка Web в «Platform status» — «Partial WASM backend» без Chrome. По
`doc/web-parity.md` на JavaScript-сборке все 42 пары операция/формат ведут себя как native (40 совпадают, 2 пары
`chromaSwap` не поддерживаются и на native). Привести README к фактам и поднять версию до 0.5.1. Статус `--wasm` здесь
не меняется — его по факту обновляет WEB 4.

#### Architect Decision

1. **README.md:**
   - вступление: вместо «Web uses a partial WASM backend» — Web использует WASM backend через JavaScript-сборку Flutter;
   - «Installation»: `yuv_ffi: 0.5.1`; абзац про 0.2.4/0.4.0 сохранить;
   - «Platform status», строка Web: Support — `WASM backend (JavaScript build); operation parity with native`,
     Checked in CI — `Package checks, browser tests, and the 1188-case correctness matrix`, Checked manually — `Chrome`;
   - раздел «Web backend» переписать по `doc/web-parity.md`: на JavaScript-сборке операции совпадают с native
     (проверено в Chrome; `chromaSwap` — только NV12, как на native); `flutter build web --wasm` собирается, но
     операции падают при выполнении — пока не поддерживается; Safari и Firefox — not verified (D-27). Совет про
     `YuvCapabilities` сохранить;
   - «Safari and Firefox have not been tested» → «have not been verified» (D-27);
   - строка iOS в «Platform status»: ручная проверка на iPhone — release-сборка (APPLE 1), не debug.
2. **Версия 0.5.1** в четырёх файлах D-14 (`pubspec.yaml`, `CHANGELOG.md`, `darwin/yuv_ffi.podspec`,
   `src/CMakeLists.txt` — `project(... VERSION 0.5.1 ...)` и `YUV_FFI_PACKAGE_VERSION`) и в `example/pubspec.lock`
   (`flutter pub get` в `example/`; прочие изменения lockfile откатить).
3. **CHANGELOG.md:** верхняя запись `## 0.5.1`, раздел `### Documentation`: `Clarified Web support: operations match
   native on the JavaScript build (verified in Chrome); corrected the platform status table.` WEB 4 дописывает в ту же
   запись.
4. `doc/web-parity.md` не меняется.

#### Scope

`README.md`, `CHANGELOG.md`, `pubspec.yaml`, `darwin/yuv_ffi.podspec`, `src/CMakeLists.txt` (только номер версии),
`example/pubspec.lock`.

#### Constraints

- `lib/`, `src/` (кроме номера версии), `example/lib/`, `assets/` не меняются.
- Не обещать больше проверенного: только Chrome, только JavaScript-сборка.

#### Definition of Done

- «Requirements», «Platform status» и «Web backend» в README не противоречат друг другу и `doc/web-parity.md`.
- Версия `0.5.1` одинакова в четырёх файлах D-14, README и `example/pubspec.lock`; верхняя запись CHANGELOG — `0.5.1`.

#### Validation

- Executor: `rg -n "0\.5\.[01]" pubspec.yaml CHANGELOG.md darwin/yuv_ffi.podspec src/CMakeLists.txt README.md` и
  версия `yuv_ffi` в `example/pubspec.lock`; `git diff <base> --stat` — только файлы Scope. Проба `windows` —
  `pwsh -File tool/ci/windows.ps1` один раз для пула после CI 1.
- Reviewer: прочитать README против `doc/web-parity.md`; Pixel 3 arm64 и armv7 — `tool/probe/run_release_android.ps1`
  один раз на принятом SHA пула.

#### Executor Report

- Обновлены README и верхняя запись CHANGELOG, версия приведена к `0.5.1` в четырёх файлах D-14 и `example/pubspec.lock`.
- `flutter pub get` (cwd `example/`) — exit 0; изменился только path-зависимый `yuv_ffi` с `0.5.0` на `0.5.1`.
- `bash tool/ci/scope_guard.sh 6986feb295e4b1ebbdc2139313044282d5b0daa5` — `scope: all`.
- `pwsh -File tool/ci/windows.ps1` — PASS, 134/134 VM-tag tests, Windows release build и все пять native integration targets.
- `pwsh -File tool/ci/web.ps1` — PASS на SHA `8ebc4088fab73bdf25741e30c071a1c8d11abcd8`; Android/Apple/Linux результаты общего пула записаны в CI 1.
- Pixel 3 arm64/armv7 проверяет Reviewer на принятом SHA.

#### Review
