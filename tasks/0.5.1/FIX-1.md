# FIX 1 — README: точный статус Web и платформ (патч 0.5.1)
**Status:** TODO · **Tier:** T3, Reviewer T2 · **Owner:** — · **Depends On:** — · **Probe:** none

**Base SHA:** —

#### Goal

Опубликованный README 0.5.0 занижает поддержку Web: раздел «Web backend» пишет «work in progress» и «not
feature-complete with native backends», строка Web в «Platform status» — «Partial WASM backend» без Chrome. По
`doc/web-parity.md` на JavaScript-сборке все 42 пары операция/формат ведут себя как native (40 совпадают, 2 пары
`chromaSwap` не поддерживаются и на native); не поддержан только `--wasm`. README на pub.dev меняется только новой
версией — выпустить 0.5.1 с исправленной документацией. Код не меняется.

#### Architect Decision

1. **README.md:**
   - вступление (`Web uses a partial WASM backend`) — Web использует WASM backend через JavaScript-сборку Flutter;
   - «Platform status», строка Web: Support — `WASM backend (JavaScript build); operation parity with native`,
     Checked in CI — `Package checks, browser tests, and the 1188-case correctness matrix`, Checked manually — `Chrome`;
   - раздел «Web backend» переписать по фактам `doc/web-parity.md`: операции совпадают с native на JavaScript-сборке
     (проверено в Chrome); `flutter build web --wasm` собирается, но операции падают при выполнении — пока не
     поддерживается; Safari и Firefox — not verified (D-27). Совет про `YuvCapabilities` сохранить;
   - «Safari and Firefox have not been tested» → «not verified» (D-27);
   - строка iOS в «Platform status»: ручная проверка на iPhone — release-сборка (APPLE 1), не debug.
2. **Версия 0.5.1** в четырёх файлах D-14 (`pubspec.yaml`, `CHANGELOG.md`, `darwin/yuv_ffi.podspec`,
   `src/CMakeLists.txt`) и в `example/pubspec.lock` (через `flutter pub get` в `example/`). В README — `yuv_ffi: 0.5.1`.
3. **CHANGELOG.md:** новая верхняя запись `## 0.5.1` — `Documentation: clarified Web support (operation parity with
   native on the JavaScript build, verified in Chrome; --wasm not supported yet) and the platform status table.`
4. `doc/web-parity.md` не меняется: он уже точен.

#### Scope

`README.md`, `CHANGELOG.md`, `pubspec.yaml`, `darwin/yuv_ffi.podspec`, `src/CMakeLists.txt` (только номер версии),
`example/pubspec.lock`.

#### Constraints

- `lib/`, `src/` (кроме номера версии), `example/lib/`, `assets/` не меняются.
- Не обещать больше, чем проверено: только Chrome, только JavaScript-сборка.
- Тег и публикация — Engineer.

#### Definition of Done

- README и CHANGELOG описывают Web по `doc/web-parity.md`; противоречий между «Requirements», «Platform status» и
  «Web backend» нет.
- Версия `0.5.1` одинакова в четырёх файлах D-14, README и `example/pubspec.lock`.
- На SHA кандидата: `flutter pub publish --dry-run` — 0 warnings; `pana --exit-code-threshold 0 .` на Mac — 160/160;
  `ci/all/0.5.1` — 9/9. Дерево чистое.

#### Validation

- Executor: `git diff <base>..<SHA> --stat` — только файлы Scope; dry-run, pana и CI на одном SHA; ссылки на run в
  отчёте. Pixel 3 и локальные платформенные скрипты не нужны: код не меняется (решение Engineer 05.10.2026).
- Reviewer: прочитать новый раздел Web против `doc/web-parity.md`, сверить версии, повторить dry-run.

#### Executor Report

#### Review
