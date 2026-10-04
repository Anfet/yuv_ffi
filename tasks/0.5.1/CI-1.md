# CI 1 — Web CI: обязательный прогон `--wasm`
**Status:** BLOCKED · **Tier:** T3, Reviewer T2 · **Owner:** Engineer · **Depends On:** WEB 4 · **Probe:** none

**Base SHA:** — (база пула `WASM` — в FIX 1)

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
- **BLOCKED:** scope guard печатает `all`; Linux VM доступна в перечне обязательных проверок, но два SSH вызова к `192.168.1.29:22` завершились `Connection timed out` (синхронизация и повтор `flutter --version`). Для снятия блокировки Engineer должен поднять Linux VM/SSH. Повторить на ней по `AGENTS.md`: в `example/` выполнить `flutter create --platforms=linux .`, затем `xvfb-run -a bash tool/ci/drive.sh integration_test/<target> linux`.
- Baseline archive для негативного контроля создан в `C:\Users\Oleg-T\AppData\Local\Temp\yuv-ffi-baseline-6986feb`. Автоматическая проверка отклонила удаление временной папки (`Remove-Item -Recurse`), поэтому она оставлена на диске.

#### Review
