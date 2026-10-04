# AGENTS — yuv_ffi

Правила этого проекта поверх общих `D:\.projects\AGENTS.md`, `CODESTYLE.md` и `ENGINEERING_PROTOCOL.md`. План, этапы,
статусы и решения Engineer (D-N) — в `todo.md`.

## Границы

- `build/` и пути из `.ignore` не читать, не искать и не анализировать.
- Сгенерированные FFI bindings (`lib/src/functions/bindings/yuv_ffi_bingings.dart`) руками не править: изменить
  заголовки или `ffigen.yaml` и перегенерировать — `dart run ffigen --config ffigen.yaml`.
- Native C (`src/`) меняется только как работа задачи: изменение явно описано в Architect Decision карточки или сама
  задача — native-изменение с известным решением (D-17). Пробных и временных правок `src/` нет.
- Платформенные реализации — в каталогах `impl/`, с суффиксом `_io` (native) или `_web` (Web). Общие интерфейсы и
  типы — вне `impl/`.
- Web — частичный WASM backend (`lib/src/yuv/impl/web/yuv_web.dart`); не описывать его как паритет с native.

## Версия и CHANGELOG

- Новые изменения — в верхнюю запись `CHANGELOG.md`; версия в `pubspec.yaml` равна верхней записи.
- Номер версии везде один: `pubspec.yaml`, `CHANGELOG.md`, `darwin/yuv_ffi.podspec`, `src/CMakeLists.txt` (D-14).

## Ветки и задачи

- Работа — прямо в `dev` в основной копии `D:\.projects\yuv_ffi`, без worktree и веток пула (D-22, D-25). На старте
  пула Executor записывает в карточку базовый SHA `dev`; ревью — диапазон `<base>..<SHA>`.
- ID задачи — слово области и номер: в тексте через неразрывный пробел (TEST 1), в имени карточки через дефис
  (`tasks/<версия>/TEST-1.md`). Карточки, дашборд и статусы — по `todo.md` и `ENGINEERING_PROTOCOL.md`.
- История — в git. После `DONE` карточка удаляется, в `COMPLETION.md` остаётся одна строка. Сырые замеры не
  коммитятся: вывод, который остаётся в силе, — строкой в `doc/perf-findings.md`.

## Пробы

- Проба проверяет backend, через который проходит изменённый код. Каждая карточка объявляет `Probe:` — `none` или
  набор из `windows`, `pixel3`, `web` через `+` (например, `windows+pixel3+web`). Набор — объединение строк таблицы
  для всех изменённых путей:

  | Пути | Probe |
  | --- | --- |
  | `src/**`; native-путь Dart: `lib/src/yuv/impl/io/**`, `lib/src/functions/**`, `lib/src/loader/impl/*_io.dart` | `windows+pixel3` |
  | ABI-контракт обоих backend: `lib/src/yuv/shared/yuv_abi_v1_*`, `lib/src/yuv/shared/yuv_native_status.dart` | `windows+pixel3+web` |
  | Web-путь: `lib/src/yuv/impl/web/**`, `lib/src/web/**`, `lib/src/loader/impl/*_web.dart`, `assets/wasm/**`, `tool/wasm/**` | `web` |
  | Прочий общий код операций: `lib/src/yuv/**` вне `impl/io` и `impl/web`, `lib/src/yuv_*.dart` | `windows+web` |
  | Остальное в `lib/` (`widgets/`, `geometry/`), `example/`, `test/`, документы, CI, `tool/` | `none` |

  Утверждение о скорости добавляет пробу каждого backend, о котором оно сделано (native — `windows+pixel3`, Web —
  `web`). Изменение `src/`, после которого пересобираются WASM-артефакты, добавляет `web`. Изменения только в
  комментариях карточка может понизить явно, с причиной. Обязательные проверки по `scope_guard.sh` от пробы не
  зависят.
- Executor запускает пробы `windows` (в составе `tool/ci/windows.ps1`) и `web` (в составе `tool/ci/web.ps1`) и пишет
  их вердикты в отчёт: `FAIL` не сдаётся, `SLOWER` объясняется или исправляется.
- Для `pixel3` Reviewer запускает пробу на Pixel 3 arm64, для `src/` — ещё armv7. Обновление baseline — дело
  Reviewer, отдельным коммитом с причиной.

## Локальные проверки

Ключи для изменённых путей печатает `bash tool/ci/scope_guard.sh <base>` (источник правды — `path_keys()` в
скрипте); `all` — все доступные команды. Документы (`*.md`, `doc/`, `tasks/`) проверок не требуют.

| Ключ | Команда | Где |
| --- | --- | --- |
| `vm` | `pwsh -File tool/ci/vm.ps1` | Windows |
| `windows` | `pwsh -File tool/ci/windows.ps1` | Windows |
| `android` | `pwsh -File tool/ci/android.ps1` | Windows, Android SDK и AVD |
| `web` | `pwsh -File tool/ci/web.ps1` | Windows, Chrome и Emscripten |
| `example` | `pwsh -File tool/ci/example.ps1` | Windows |
| `smoke` | `pwsh -File tool/ci/smoke.ps1` | Windows (проверка CI-хелперов) |
| `macos` | `bash tool/ci/macos.sh` | Mac |
| `ios` | `bash tool/ci/ios.sh` | Mac, Xcode и симулятор |
| `linux` | в `example/`: `flutter create --platforms=linux .`, затем `xvfb-run -a bash tool/ci/drive.sh integration_test/<target> linux` | Linux VM (`todo.md`, «Окружение») |

Для `src/**` дополнительно: `flutter test --tags probe`, `flutter test --tags reference` и native CTest:

```sh
cmake -S . -B <temp> -DBUILD_TESTING=ON
cmake --build <temp> --config Release
ctest --test-dir <temp> -C Release --output-on-failure
```

### Выборочные тесты

- По тегам, из корня пакета: `flutter test --tags "smoke || contract"` (его запускает `vm.ps1`), `--tags probe`,
  `--tags reference`, `--tags release`; полный `flutter test` — только если требует карточка.
- Срез пробы: переменные `PROBE_OPS` и `PROBE_FORMATS` (VM) или те же `--dart-define` (`flutter drive`); фактический
  срез — строка `PROBE scope: ops=... formats=... cases=N/total`. Пример VM:
  `$env:PROBE_OPS='gray'; flutter test test/probe/probe_correctness_test.dart`. Web — при запущенном ChromeDriver:
  `pwsh -File tool/ci/drive.ps1 integration_test/probe_web_test.dart web-server --browser-name=chrome --headless --dart-define=PROBE_OPS=gray --dart-define=PROBE_FORMATS=i420`
  (target — относительно `example/`).

## CI

- Автозапуска нет (D-23): CI запускается тегом `ci/<набор>/<метка>` на точный SHA или вручную (`workflow_dispatch`).
  Набор — `all` или одна платформа: `vm`, `windows`, `macos`, `ios`, `android`, `web`, `example`, `smoke`, `linux`.
  Основная проверка — локальные скрипты выше.
- Один workflow — одна платформа: `.github/workflows/ci-<name>.yml` (Linux и регенерация bindings — `ci.yml`) делает
  checkout, выбирает runner и запускает `tool/ci/<name>.ps1` (Windows) или `.sh` (Linux, macOS); тот же скрипт
  запускается локально.
- `flutter drive` возвращает 0 и при провале: `tool/ci/drive.ps1` и `drive.sh` принимают результат только при exit 0 и
  строке `All tests passed`. Не вызывать `flutter drive` напрямую.
