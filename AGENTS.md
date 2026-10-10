# AGENTS — yuv_ffi

Memory: D:\.projects\yuv\.memory\MEMORY.md

Правила этого проекта поверх общих `D:\.projects\AGENTS.md`, `CODESTYLE.md` и `ENGINEERING_PROTOCOL.md`. План, этапы,
статусы и решения Engineer (D-N) — в `D:\.projects\yuv\todo.md`.

## Границы

- `build/` и пути из `.ignore` не читать, не искать и не анализировать.
- Сгенерированные FFI bindings (`lib/src/functions/bindings/yuv_ffi_bingings.dart`) руками не править: изменить
  заголовки или `ffigen.yaml` и перегенерировать — `dart run ffigen --config ffigen.yaml`.
- Native C (`src/`) меняется только как работа задачи: изменение явно описано в Architect Decision карточки или сама
  задача — native-изменение с известным решением (D-17). Пробных и временных правок `src/` нет.
- Платформенные реализации — в каталогах `impl/`, с суффиксом `_io` (native) или `_web` (Web). Общие интерфейсы и
  типы — вне `impl/`.
- Web — WASM backend (`lib/src/yuv/impl/web/yuv_web.dart`). Паритет с native описывать только в пределах
  проверенного (`doc/web-parity.md`): операции, сборка (JavaScript / `--wasm`) и браузеры называются явно.

## Версия и CHANGELOG

- Новые изменения — в верхнюю запись `CHANGELOG.md`; версия в `pubspec.yaml` равна верхней записи.
- Номер версии везде один: `pubspec.yaml`, `CHANGELOG.md`, `darwin/yuv_ffi.podspec`, `src/CMakeLists.txt` (D-14).

## Ветки и задачи

- Работа — прямо в `dev` в checkout `D:\.projects\yuv\yuv_ffi`, без worktree и веток пула (D-22, D-25). На старте
  пула Executor записывает в центральную карточку базовый SHA этого репозитория; ревью — диапазон `<base>..<SHA>`.
- ID задачи — слово области и номер: в тексте через неразрывный пробел (TEST 1), в имени карточки через дефис
  (`tasks/<версия>/TEST-1.md` в group checkout `D:\.projects\yuv`). Карточки, дашборд и статусы — по
  `D:\.projects\yuv\todo.md` и `ENGINEERING_PROTOCOL.md`.
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
  | Остальное в `lib/` (`widgets/`, `geometry/`), `example/`, `test/`, документы, `tool/` | `none` |

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
скрипте); `all` — все команды таблицы, включая `bindings`. Документы (`*.md`, `doc/`, `tasks/`) проверок не требуют.
Каталог `tool/ci/` — имя каталога scripts; что каждый script заменяет из удалённых workflows — `doc/validation.md`.

| Ключ | Команда | Где |
| --- | --- | --- |
| `vm` | `pwsh -File tool/ci/vm.ps1` | Windows |
| `windows` | `pwsh -File tool/ci/windows.ps1` | Windows |
| `android` | `pwsh -File tool/ci/android.ps1` | Windows, Android SDK и AVD |
| `web` | Windows: `pwsh -File tool/ci/web.ps1`; Mac: `bash tool/ci/web.sh` | Windows/Mac, Chrome и Emscripten |
| `example` | `FLUTTER_VERSION=3.44.9`, затем `pwsh -File tool/ci/example.ps1` | Windows |
| `smoke` | `pwsh -File tool/ci/smoke.ps1` | Windows (проверка helpers в `tool/ci/`) |
| `macos` | `bash tool/ci/macos.sh` | Mac |
| `ios` | `bash tool/ci/ios.sh` | Mac, Xcode и симулятор |
| `linux` | `bash tool/ci/linux.sh` | Ubuntu VM: clang, cmake, ninja, GTK 3, xvfb (MACHINES) |
| `bindings` | `bash tool/ci/bindings.sh` в чистой копии точного коммита (`git archive` или clone) | Mac, Xcode |

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

## Приёмка и выпуск без CI (D-38)

- GitHub Actions workflows у пакета нет, CI не запускается и CI-теги не ставятся. Все проверки — команды таблицы выше
  на собственных машинах (Windows, Ubuntu VM, Mac) и устройствах; доступ к машинам — `D:\.projects\MACHINES.md`.
- Приёмка карточки: ключи `scope_guard.sh` от базы карточки и её `Probe:`. Ключ `bindings` (`ffigen.yaml`,
  сгенерированные bindings, заголовки; входит в `all`) обязателен при таком scope.
- Перед каждым выпуском каждой версии — полный обязательный набор на чистом закоммиченном кандидате, независимо от
  scope последней карточки: все ключи таблицы, включая `linux` и `bindings`, полный `flutter test` корня и example,
  устройства по релизному гейту group `todo.md`. Прежний PASS или перенос проверки в script не заменяет прогон.
- Отчёт: `Validated at` (полный SHA), машина и версии SDK, команда, exit code и критерий PASS script. Результат на
  другом SHA допустим только при пустом `git diff <Validated at>..<SHA> --stat -- <покрываемые пути>`.
- `flutter drive` возвращает 0 и при провале: `tool/ci/drive.ps1` и `drive.sh` принимают результат только при exit 0 и
  строке `All tests passed`. Не вызывать `flutter drive` напрямую.
