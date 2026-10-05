# CI 1 — Web CI: обязательный прогон `--wasm`
**Status:** BLOCKED · **Tier:** T3, Reviewer T2 · **Owner:** Engineer · **Depends On:** WEB 4 · **Probe:** none

**Base SHA:** `6986feb295e4b1ebbdc2139313044282d5b0daa5` (`dev` на старте пула `WASM`)

#### Goal

Сборка `--wasm` сломалась незаметно: `tool/ci/web.ps1` гоняет только JavaScript-сборку. После WEB 4 Web CI должен
ловить регрессию `--wasm` так же, как JavaScript.

#### Architect Decision

1. В `tool/ci/web.ps1` после JavaScript-целей — шаг `--wasm` через существующий `Invoke-WebDrive` с аргументом
   `--wasm`: `probe_web_test.dart`, `shader_probe_web_test.dart`, `all_web_test.dart`. Ожидаемые числа тестов — те же,
   что в таблице `web.ps1` для этих целей. Шаг обязательный: провал любой цели — провал скрипта. Отдельного
   переключателя нет.
2. `reference_web_conversions_test.dart` и камера под `--wasm` в CI не гоняются (покрыты пробой и WEB 4); время
   шага — в отчёт.
3. Workflow `ci-web.yml` не меняется: он вызывает `web.ps1`.
4. Если WEB 4 закрылся без рабочего `--wasm` (`ENGINEER_REQUIRED`), карточка переходит в `BLOCKED` до решения Engineer.

#### Scope

`tool/ci/web.ps1`.

#### Constraints

- JavaScript-часть `web.ps1` и её критерии не меняются.
- ChromeDriver запускается и останавливается как сейчас (порт 4444, сверка major-версий).

#### Definition of Done

- `pwsh -File tool/ci/web.ps1` — PASS, в выводе три цели `--wasm` с `All tests passed`.
- Негативный контроль: шаг `--wasm` на базовом SHA пула (до WEB 4, временный checkout вне основной копии) падает.

#### Validation

- Executor: `pwsh -File tool/ci/web.ps1` на SHA пула; негативный контроль; `bash tool/ci/scope_guard.sh <base>` —
  ключ `smoke`, если его печатает.
- Reviewer: прочитать изменение `web.ps1`; после принятия — тег `ci/web/WASM` на принятый SHA, Web CI зелёный.

#### Executor Report

- Добавлен обязательный шаг `--wasm` после JavaScript-целей: `probe_web_test.dart`, `shader_probe_web_test.dart`, `all_web_test.dart`; каждую цель пропускает через `Invoke-WebDrive`, который требует `All tests passed`.
- `pwsh -File tool/ci/web.ps1` на SHA `8ebc4088fab73bdf25741e30c071a1c8d11abcd8` — PASS: JS 14 sources/64 cases, reference 119, camera smoke, три WASM цели; WASM шаг 1:38.
- `pwsh -File tool/ci/vm.ps1` — PASS (638/638); `pwsh -File tool/ci/windows.ps1` — PASS (134/134, Windows build и five integration targets); `pwsh -File tool/ci/android.ps1` — PASS (ABI split builds, пять integration targets на Tablet AVD).
- `pwsh -File tool/ci/example.ps1` (`FLUTTER_VERSION=3.44.9`) — PASS (analyze, web build); `pwsh -File tool/ci/smoke.ps1` — PASS.
- `flutter test --tags probe` — PASS (1188/1188, `PROBE scope: ops=all formats=all cases=1188/1188`) and `flutter test --tags reference` — PASS (130 tests), using the native DLL directory built by `windows.ps1`. The first direct probe invocation lacked that directory in PATH and failed to load `yuv_ffi.dll`; rerun with the CI DLL path passed.
- Native CTest via CMake 3.22.1 — PASS, 11/11 (`cmake -S . -B <temp> -DBUILD_TESTING=ON`, build Release, `ctest --test-dir <temp> -C Release --output-on-failure`).
- `macos.sh` и `ios.sh` на Mac — exit 0. macOS native tests, release build, CocoaPods fallback прошли; финальная git-status проверка напечатала `fatal: not a git repository`, так как синхронизированная копия сделана через `git archive` без `.git`. iOS Simulator/device builds и пять simulator integration targets прошли.
- Негативный контроль на временной `git archive` копии базы `6986feb295e4b1ebbdc2139313044282d5b0daa5`: `drive.ps1 ... probe_web_test.dart ... --wasm` — ожидаемый exit 1, probe показал `got ERR StateError`.
- Linux scope check на `b7ce1f8` — PASS: Flutter 3.44.9; sanitizer CTest Debug и Release — 11/11 в каждом; sanitizer case count; native packaging smoke; `flutter build linux --release`; app-runtime smoke и все четыре найденных `_native_test.dart` targets через `drive.sh` — PASS. `example/pubspec.lock` совпал с файлом из commit archive после `flutter pub get`.
- Baseline archive для негативного контроля создан в `C:\Users\Oleg-T\AppData\Local\Temp\yuv-ffi-baseline-6986feb`. Автоматическая проверка отклонила удаление временной папки (`Remove-Item -Recurse`), поэтому она оставлена на диске.

#### Review

**Код принят, карточка ждёт зелёного Web CI** (Reviewer, 05.10.2026; SHA `1866a2d155cc241b1e0b0af7f71e23398b2637e1`).

- Изменение `tool/ci/web.ps1` соответствует решению: обязательный шаг `--wasm` после JavaScript-целей, три цели через `Invoke-WebDrive` (критерий `drive.ps1` — exit 0 и `All tests passed`), без переключателя; JavaScript-часть, ChromeDriver (порт 4444) и `ci-web.yml` не менялись.
- Локально на `1866a2d`: `pwsh -File tool/ci/web.ps1` — exit 0; три цели `--wasm` PASS, шаг 48 с.
- Негативный контроль повторён на чистом `git archive 6986feb` (scratchpad): `drive.ps1 integration_test/probe_web_test.dart web-server --browser-name=chrome --headless --wasm` — exit 1, `got ERR StateError`.
- CI: тег `ci/web/WASM` на `1866a2d` → run 37243974376 (https://github.com/Anfet/yuv_ffi/actions/runs/37243974376) — **failure**: шаг «Run Web checks» без заключения через 42 мин, аннотация «The self-hosted runner lost communication with the server». Раннер `dev.working` после этого `offline` в GitHub, хотя служба `actions.runner.Anfet-yuv_ffi.dev.working` локально `Running`. Лог задания недоступен (BlobNotFound). Диагноз не ставится.
- Следующий шаг: Engineer возвращает раннер `dev.working` в `online`; затем перезапуск run (или новый тег `ci/web/WASM-2` на `1866a2d`); при зелёном — `ACCEPTED`.
