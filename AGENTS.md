# AGENTS — yuv_ffi

Memory: D:\.projects\yuv\.memory\MEMORY.md

Правила этого проекта поверх общих `D:\.projects\AGENTS.md`, `D:\.projects\.tools\skills\project-codestyle\SKILL.md` и `D:\.projects\.tools\skills\engineering-protocol\SKILL.md`. План, этапы,
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
  `D:\.projects\yuv\todo.md` и `D:\.projects\.tools\skills\engineering-protocol\SKILL.md`.
- История — в git. После `DONE` карточка удаляется, в `COMPLETION.md` остаётся одна строка. Сырые замеры не
  коммитятся: вывод, который остаётся в силе, — строкой в `doc/perf-findings.md`.

## Пробы

- Выбор проверок — по [общей политике](../doc/release-validation-policy.md). `Probe:` карточки — `none` или
  выбранные `windows`, `pixel3`, `web`; каждый дополнительный backend обосновывается изменённым путём/риском
  и недостаточностью VM/native. Наличие `src/` само по себе не требует Pixel/WASM.
- Обычный численный C-fix: Windows VM с настоящей native-библиотекой и эталонными результатами изменённой операции;
  существующий native unit target добавляется для отдельного риска. ABI/память сначала проверяются затронутыми
  VM/native cases; ARM/NEON, WASM SIMD, ifdef и compiler flags — соответствующим target. Apple static linkage —
  Apple static consumer, без подмены Windows PASS. Сборка изменённых WASM assets требует соответствующей Web-проверки.
- Утверждение о скорости требует пробы именно backend/архитектуры, о которых сделано утверждение.
  Срез задают `PROBE_OPS`/`PROBE_FORMATS`; фактический набор подтверждает `PROBE scope`.
- Executor выполняет Validation карточки; Reviewer читает достаточные результаты без обязательного повтора Pixel
  arm64/armv7. Обновление baseline остаётся отдельным обоснованным изменением Reviewer, не автоматическим шагом.

## Локальные проверки

Ключи для изменённых путей печатает `bash tool/ci/scope_guard.sh <base>` (источник правды — `path_keys()` в
скрипте); `all` перечисляет возможное влияние, включая `bindings`, а не обязательные команды. Документы требуют
чтения diff/ссылок; runtime не нужен. Фактический набор — Validation карточки по общей политике.
Каталог `tool/ci/` — имя каталога scripts; что каждый script заменяет из удалённых workflows — `doc/validation.md`.

| Ключ | Команда | Где |
| --- | --- | --- |
| `vm` | `pwsh -File tool/ci/vm.ps1` | Windows |
| `windows` | `pwsh -File tool/ci/windows.ps1` | Windows |
| `android` | `pwsh -File tool/ci/android.ps1` | Windows + Pixel 3 по USB (`ANDROID_SERIAL=8B1X11QLW`), экран включён и разблокирован; эмуляторы не используются |
| `web` | Windows: `pwsh -File tool/ci/web.ps1`; Mac: `bash tool/ci/web.sh` | Windows/Mac, Chrome и Emscripten |
| `example` | `FLUTTER_VERSION=3.44.9`, затем `pwsh -File tool/ci/example.ps1` | Windows |
| `smoke` | `pwsh -File tool/ci/smoke.ps1` | Windows (проверка helpers в `tool/ci/`) |
| `macos` | `bash tool/ci/macos.sh` | Mac |
| `ios` | `bash tool/ci/ios.sh` | Mac, Xcode и симулятор |
| `linux` | `bash tool/ci/linux.sh` | Ubuntu VM: clang, cmake, ninja, GTK 3, xvfb (machine-use) |
| `bindings` | `bash tool/ci/bindings.sh` в чистой копии точного коммита (`git archive` или clone) | Mac, Xcode |

Для `src/**` не назначать автоматически полные `probe`, `reference` и CTest. Выбрать регрессию изменённой
операции и существующий native target, если он закрывает отдельный риск; конкретные команды фиксируются в карточке.
Тесты и критерии PASS сохраняются, полный набор доступен для обоснованной задачи.

### Выборочные тесты

- `tool/ci/vm.ps1`: `-TestPath`, `-Name`, `-Group`, `-List`; группы `codec`, `state`, `pixel-format`, `presenter`.
  `-TestPath` и `-Group` взаимоисключающие; `-Name` фильтрует выбранный набор, `-List` только печатает выбор.
  Targeted режим не делает общий analyze: нужен отдельный targeted analyze изменённого модуля.
  Синтаксис одиночных drive targets и group `-OnlyRow` — в [общей политике](../doc/release-validation-policy.md#существующие-точечные-команды-и-автоматизация).

- По тегам, из корня пакета: `flutter test --tags "smoke || contract"` (его запускает `vm.ps1`), `--tags probe`,
  `--tags reference`, `--tags release`; полный `flutter test` — только если требует карточка.
- Срез пробы: переменные `PROBE_OPS` и `PROBE_FORMATS` (VM) или те же `--dart-define` (`flutter drive`); фактический
  срез — строка `PROBE scope: ops=... formats=... cases=N/total`. Пример VM:
  `$env:PROBE_OPS='gray'; flutter test test/probe/probe_correctness_test.dart`. Web — при запущенном ChromeDriver:
  `pwsh -File tool/ci/drive.ps1 integration_test/probe_web_test.dart web-server --browser-name=chrome --headless --dart-define=PROBE_OPS=gray --dart-define=PROBE_FORMATS=i420`
  (target — относительно `example/`).

## Приёмка и выпуск без CI (D-38)

- GitHub Actions workflows у пакета нет, CI не запускается и CI-теги не ставятся. Все проверки — команды таблицы выше
  на собственных машинах (Windows, Ubuntu VM, Mac) и устройствах; доступ к машинам — `D:\.projects\.tools\private-skills\machine-use\SKILL.md`.
- Приёмка карточки: проверки её Validation по [общей политике](../doc/release-validation-policy.md).
  Для рассмотренных scope/Probe ключей записать RUN / CARRIED / NOT_REQUIRED / PENDING с основанием;
  требуемый отложенный результат имеет конкретный этап/владельца. `all` не требует полного прогона.
- Перед выпуском проверить полноту необходимых результатов на чистом закоммиченном кандидате: новые результаты
  только для изменённого поведения/config/dependencies, остальные — доказанный CARRIED. Версия/SHA не требуют
  полного runtime. Изменённый publish payload требует inventory/dry-run; если нужен `web.ps1 -Release`, он включает
  пересборку WASM и dry-run. Новая платформа/конфигурация требует своего первичного результата.
- Отчёт: отдельный полный `Validated at` этого пакета, машина/SDK, команда, exit code и критерий PASS.
  Перенос — по covered behavior/config/dependencies и правилам общей политики, включая комментарии без изменения поведения.
  Windows PASS не заменяет Apple/WASM; machine actions выполняет агент, человек — только реальная подготовка/oracle.
- `flutter drive` возвращает 0 и при провале: `tool/ci/drive.ps1` и `drive.sh` принимают результат только при exit 0 и
  строке `All tests passed`. Не вызывать `flutter drive` напрямую.
