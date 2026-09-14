# yuv_ffi: план исправлений после аудита

Актуально для ветки `release/0.2.4`, commit `5f52fd1` и tag `0.2.4`.

Цель: устранить найденные release-блокеры, восстановить воспроизводимые проверки Web/native и подготовить следующий исправляющий релиз. Текущий `0.2.4` нельзя считать готовым к публикации, пока задачи уровня P0/P1 не приняты.

## Общий чеклист

| Готово | ID | Владелец | Anthropic-вариант | Приоритет | Статус | Зависит от | Краткое описание |
|---|---|---|---|---|---|---|---|
| [ ] | YUV-06 | Terra | Claude Opus 5 | P1 | BLOCKED | разрешение на C | Восстановить загрузку и упаковку native-библиотеки на Linux/macOS |
| [ ] | YUV-08 | Luna | Claude Sonnet 5 | P2 | TODO | — | Восстановить Web parity для padded BGRA и публичного tight-buffer контракта |
| [ ] | YUV-09 | Luna | Claude Sonnet 5 | P2 | BLOCKED | YUV-06, YUV-08, YUV-13, YUV-22, YUV-23, YUV-30, YUV-32 | Синхронизировать README, platform matrix и локальный analyzer workflow |
| [ ] | YUV-12 | Luna | Claude Sonnet 5 | P1 | TODO | — | Прогнать ту же матрицу по эталону на реальном Web/WASM backend |
| [ ] | YUV-13 | Terra | Claude Sonnet 5 | P1 | BLOCKED | YUV-11, YUV-12 | Проверить полноту матрицы и оформить все падения в `failed-test-cases.md` |
| [ ] | YUV-21 | Opus | Claude Opus 5 | P1 | REJECTED | доказать удаление failed DOM script без reuse старой factory | Зафиксировать retry/error/lazy-init контракт IO и Web |
| [ ] | YUV-22 | Opus | Claude Opus 5 | P1 | BLOCKED | YUV-30, YUV-33, разрешение на C | Зафиксировать RGB-visible effects contract, logical-sample addressing и odd chroma |
| [ ] | YUV-23 | Opus | Claude Opus 5 | P0 | BLOCKED | YUV-30, YUV-33, разрешение на C | Исправить blur memory safety, параметры, snapshot semantics и межформатный контракт |
| [ ] | YUV-24 | Terra | Claude Sonnet 5 | P2 | BLOCKED | разрешение на C | Устранить дубли и восстановить пересборку glob в `src/CMakeLists.txt` |
| [ ] | YUV-26 | Luna | Claude Haiku 4.5 | P3 | DELAYED | добавить Unix regeneration evidence | Ограничить ffigen только используемым ABI и убрать platform CRT из bindings |
| [ ] | YUV-28 | Opus | Claude Opus 5 | P2 | BLOCKED | после YUV-18 | Сократить дублирование backend-классов после релиза `0.2.5` |
| [ ] | YUV-29 | Luna | Claude Haiku 4.5 | P3 | BLOCKED | разрешение на C headers | Удалить неиспользуемое объявление `nv21_to_rgb` без реализации |
| [ ] | YUV-30 | Root | Claude Opus 5 | P0 | DISCOVERED | решение владельца по 5 контрактам | Зафиксировать blur/effects/ROI/parameter policy до изменения native C |
| [ ] | YUV-31 | Opus | Claude Opus 5 | P0 | BLOCKED | YUV-30, YUV-33, разрешение на C | Сделать rotate/crop/flip stride-safe и корректными на odd 4:2:0 geometry |
| [ ] | YUV-32 | Opus | Claude Opus 5 | P1 | BLOCKED | YUV-30, YUV-33, разрешение на C | Унифицировать RGBA/BGRA→YUV matrix, range, rounding и 2×2 chroma reduction |
| [ ] | YUV-33 | Opus | Claude Opus 5 | P0 | BLOCKED | YUV-30, разрешение на C | Ввести checked descriptor/index/allocation primitives для native boundary |
| [ ] | YUV-34 | Terra | Claude Sonnet 5 | P1 | BLOCKED | YUV-22, YUV-23, YUV-31…YUV-33 | Добавить ASan/UBSan canary harness и required native safety gate |
| [ ] | YUV-35 | Terra | Claude Sonnet 5 | P2 | BLOCKED | YUV-29, разрешение на C headers | Синхронизировать C ownership/mutation declarations, UV-комментарии и logging macros |
| [ ] | YUV-36 | Opus | Claude Opus 5 | P2 | BLOCKED | после `0.2.5`, YUV-33 | Спроектировать status-returning native ABI без breaking change текущих symbols |
| [ ] | YUV-37 | Terra | Claude Sonnet 5 | OPT | BLOCKED | после YUV-23 | Уменьшить allocations и сложность blur после фиксации результата |
| [ ] | YUV-38 | Terra | Claude Sonnet 5 | OPT | BLOCKED | после YUV-32 | Оптимизировать 2×2 chroma conversion без изменения reference output |
| [ ] | YUV-18 | Terra | Claude Sonnet 5 | P0 | BLOCKED | YUV-06, YUV-08, YUV-09, YUV-12, YUV-13, YUV-21…YUV-23, YUV-30…YUV-34 | Провести финальную кроссплатформенную приёмку и подготовить `0.2.5` |

## Статусы

Полные описания, решения, проверки и результаты принятых задач хранятся в
[completed-tasks.md](completed-tasks.md). После независимой приёмки и перевода
карточки в `DONE` её секцию следует переместить в архив, а в этом файле оставить
только строку доступности/зависимостей и незавершённые задачи. Перенос выполнять
в том же tracker update, что и смену статуса.

- `TODO` — задача изолирована, её зависимости выполнены и модель может взять её в работу.
- `DISCOVERED` — проблема подтверждена, но для исполнимого Architect Decision требуется решение владельца.
- `IN PROGRESS` — модель начала работу; одновременно у задачи один исполнитель.
- `BLOCKED` — не выполнена зависимость или отсутствует обязательное разрешение.
- `READY FOR REVIEW` — реализация закончена, модель приложила результат и проверки; требуется независимое ревью.
- `DONE` — инженер проверил diff, тесты и фактическое поведение и принял задачу.
- `REJECTED` — реализация возвращена с конкретным списком замечаний; после исправлений снова `READY FOR REVIEW`.

Модель не ставит своей задаче `DONE`. После реализации она меняет статус на `READY FOR REVIEW` и заполняет секцию «Результат». Статус `DONE` выставляется только после независимой проверки.

После каждого принятого `DONE` в том же tracker update необходимо пересчитать
доступность всех незавершённых карточек:

1. Если все обязательные зависимости выполнены и нужные разрешения получены,
   изменить `BLOCKED` на `TODO`.
2. Если снята только часть блокеров, оставить `BLOCKED` и удалить из колонки
   «Зависит от» уже выполненные зависимости.
3. Пометка `integration Web retest` означает, что обязательный harness уже
   доступен после принятой YUV-02, но задача не переводится в `DONE` до
   фактического выполнения своего focused case с `kIsWeb == true`.
4. После изменения доступности синхронно обновить и строку общего чеклиста, и
   секцию конкретной задачи.

### Выбор моделей

- Колонка «Владелец» сохраняет фактического или назначенного исполнителя;
  «Anthropic-вариант» — допустимая альтернатива для реализации, исправления
  после ревью или независимой проверки.
- Claude Opus 5 (`claude-opus-5`) использовать для memory safety, native C,
  сложных lifecycle и cross-backend API contracts.
- Claude Sonnet 5 (`claude-sonnet-5`) использовать для ограниченных Dart/Web
  изменений, тестовых матриц, CI и документации с несколькими связанными
  проверками.
- Claude Haiku 4.5 (`claude-haiku-4-5-20251001`) использовать только для узких
  механических задач с полностью определённым diff и DoD; при неоднозначности
  повышать до Claude Sonnet 5.
- Для воспроизводимого API-запуска закреплять точный model ID, а не полагаться
  на плавающий alias. Актуальность семейства проверена 2026-09-13 по
  [Anthropic model status](https://docs.anthropic.com/en/docs/about-claude/model-deprecations).

## Общие решения и ограничения

1. Рассинхрон имени `NV21` и фактического UV-порядка принят как установленный compatibility contract:
   - публичное имя `nv21` пока сохраняется;
   - текущий UV/NV12-like порядок байтов сохраняется;
   - нельзя «исправлять» цвета слепой перестановкой U/V;
   - любые тесты и комментарии должны явно отличать публичное legacy-имя от фактического порядка chroma.
2. Web остаётся частичным WASM backend. Исправление компиляции и тестов не означает автоматическую feature parity с native.
3. Нельзя читать, анализировать или включать в scope любые `build/` директории.
4. Нельзя вручную редактировать `lib/src/functions/bindings/yuv_ffi_bingings.dart`. При изменении ABI обновить header/`ffigen.yaml` и выполнить генерацию.
5. Любое изменение файлов `src/**/*.c`, `src/**/*.h` или platform C-forwarders запрещено до отдельного явного разрешения владельца. До него YUV-06, YUV-22, YUV-23, YUV-29 и YUV-31…YUV-35 остаются `BLOCKED`.
6. Не совмещать соседний рефакторинг с исправлением дефекта. Каждый commit должен содержать только одну задачу.
7. Не удалять локальные `_tmp_*` файлы без отдельного подтверждения владельца.
8. Не создавать tag и не выполнять push без отдельного запроса.
9. Эталон для `test/assets/test_pattern_512.png` нельзя генерировать через тестируемый native/WASM код `yuv_ffi`: иначе одинаковая ошибка окажется и в expected, и в actual.
10. Каждый новый провал эталонного теста регистрируется в `failed-test-cases.md`. Исправление не удаляет запись: она переводится в `RESOLVED` со ссылкой на commit и повторный прогон.
11. Patch-релиз `0.2.5` не должен добавлять обязательные члены в публичные
    `interface class`: это ломает внешние `implements`. Такое изменение требует
    source-compatible seam либо повышения версии до `0.3.0` по отдельному
    решению владельца.
12. Карточки, явно помеченные как опциональные или post-release, не являются
    зависимостями YUV-18 и не блокируют выпуск `0.2.5`.
13. Web runtime tests, которым нужны package assets/WASM, выполнять через
    `flutter drive` + `integration_test` на собранном example-приложении.
    `flutter test --platform chrome` не поднимает asset bundle и не считается
    доказательством для таких cases. Bootstrap job обязан быть required gate;
    `continue-on-error` допустим только для временного диагностического probe.

## Общий Definition of Done для каждой задачи

- Реализован только scope карточки; чужие и несвязанные изменения сохранены.
- Добавлен regression test, который падает на `0.2.4` и проходит после исправления, если дефект тестируем автоматически.
- Выполнены все команды из секции «Проверка» с записанными exit code и фактическим числом тестов.
- Для Web отдельно подтверждено, что тесты исполнялись с `kIsWeb == true`, а не прошли через skip-ветку.
- Для native отдельно записаны ОС, архитектура и источник загруженной библиотеки; локальный игнорируемый `yuv_ffi.dll` не считается доказательством clean-checkout CI.
- `flutter analyze` не содержит новых diagnostics.
- `dart format --output=none --set-exit-if-changed` проходит для изменённых Dart-файлов.
- `git diff --check` проходит.
- `git status --short` приложен к результату.
- Публичный `NV21`/UV compatibility contract не изменён.
- Изменения native C либо отсутствуют, либо в результате приведена ссылка на явное разрешение владельца.

## Шаблон результата модели

Скопировать в конец своей карточки:

```text
Статус: READY FOR REVIEW
Commit: <hash или "не создавался">
Изменённые файлы:
- <path>

Что сделано:
- <кратко по фактам>

Проверки:
- <команда> — exit <code>, <результат/число тестов>

Ручная проверка:
- <ОС/браузер/архитектура и наблюдаемый результат>

Остаточные риски:
- <нет или конкретный риск>

Native C permission:
- <не требовалось / ссылка на разрешение>
```

---


---

## YUV-06 — восстановить Linux/macOS packaging и runtime loading

- Владелец: Terra
- Приоритет: P1
- Статус: BLOCKED
- Зависимости: отдельное явное разрешение владельца на изменение macOS C-forwarders
- Scope:
  - `lib/src/loader/impl/loader_io.dart`
  - `linux/CMakeLists.txt`
  - `macos/yuv_ffi.podspec`
  - `macos/Classes/**`
  - CI native build/smoke matrix
  - platform support section README только после фактической проверки
- Карточка YUV-25 объединена сюда: loader path, packaging и состав macOS pod
  target имеют один release outcome и не должны расходиться по разным commits.

### Проблема

Linux и macOS loader открывает `native/src/build/libyuv_ffi.*`. Такого runtime path нет в публикуемом package/application bundle. На Linux CMake уже объявляет bundled target, который должен загружаться по имени установленной библиотеки. На Apple symbols должны находиться в process либо в корректно упакованном framework/library.

У macOS есть только один forwarder `macos/Classes/yuv_ffi.c`, подключающий агрегатор `src/yuv_ffi.c`, который сам содержит только include header. Реализации YUV/BGRA операций в macOS pod target не включены.

Текущий успешный Windows `flutter test` зависит от локального игнорируемого `yuv_ffi.dll`; это не clean-checkout доказательство.

### Зафиксированное решение

1. Использовать platform loading contract:
   - Android/Linux — установленное имя `libyuv_ffi.so`;
   - Windows — `yuv_ffi.dll`;
   - iOS/macOS — symbols текущего process, если library статически/динамически связана pod target.
2. Добавить macOS source forwarding, эквивалентный полному проверенному iOS набору, либо другой корректный podspec source layout.
3. Не дублировать одни и те же C translation units дважды.
   Исправить некритичные двойные слэши в iOS forwarder paths только внутри того
   же согласованного изменения, не отдельным cleanup-коммитом.
4. Добавить clean-checkout CI:
   - Linux и Windows: build + runtime smoke;
   - macOS: build + runtime smoke;
   - Android/iOS: как минимум plugin/example build, runtime — если инфраструктура позволяет.
5. Smoke должен вызвать `YuvFfi.ensureInitialized()` и одну реальную BGRA/YUV операцию, а не только проверить существование файла.
6. Не использовать и не публиковать локальный root `yuv_ffi.dll` как обходной путь.

### DoD

- Linux и macOS example/минимальный host собираются из clean checkout.
- `ensureInitialized()` на Linux/macOS не обращается к `native/src/build/...`.
- Все используемые generated binding symbols находятся в runtime library/process.
- Smoke conversion успешно выполняется на Windows, Linux и macOS.
- Mobile build checks проходят.
- CI не зависит от локальных бинарников разработчика.
- В результате приложено разрешение на изменение macOS C-forwarders.

### Проверка

Приложить фактические команды каждой ОС. Минимальный набор:

```text
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build <platform>
<runtime smoke command>
git diff --check
git status --short
```

Не извлекать и не анализировать содержимое `build/`; использовать только exit code команд сборки/запуска.

### Результат

Не заполнен.

---

## YUV-08 — вернуть tight BGRA contract на Web

- Владелец: Luna
- Приоритет: P2
- Статус: TODO
- Зависимости: нет (YUV-01/YUV-02/YUV-04/YUV-15 приняты; integration harness доступен)
- Scope:
  - `lib/src/yuv/impl/web/yuv_web.dart`
  - `example/integration_test/wasm_parity_edge_cases_test.dart`
  - `test/web/wasm_parity_edge_cases_test.dart` только для тестов без asset bundle
  - при необходимости shared row-repack helper

### Проблема

Публичный `toBgra8888()` обещает длину всегда `width * height * 4`. Native implementation уже repack-ит padded BGRA rows. Web для `bgra8888` возвращает копию всей `yPlane.bytes`, поэтому при `rowStride > width * 4` возвращает padding и нарушает контракт. `YuvImageWidget` затем отклоняет такой buffer по размеру.

Web edge tests покрывают padded I420/NV, но не padded BGRA.

### Зафиксированное решение

1. Повторить native semantics: при tight rowStride вернуть copy, при padding построчно скопировать только `width * 4` bytes.
2. Не менять исходную plane и не возвращать view на mutable backing buffer.
3. Добавить integration Web test с различимыми padding bytes, проверяющий и
   длину, и точный порядок pixels в реально собранном example-приложении.
4. Добавить widget-level regression либо доказать существующим тестом, что repacked buffer декодируется.

### DoD

- Web `toBgra8888()` всегда возвращает ровно `width * height * 4` bytes.
- Padding не попадает в результат.
- Native/Web padded BGRA semantics совпадают.
- Реальный Chrome integration test проходит с `kIsWeb == true`; VM skip и
  `continue-on-error` не засчитываются.

### Проверка

```powershell
Push-Location example
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/wasm_parity_edge_cases_test.dart -d chrome
Pop-Location
flutter test test/conversions_test.dart --plain-name "padded BGRA"
flutter test test/yuv_image_widget_test.dart
flutter analyze lib test
dart format --output=none --set-exit-if-changed lib test
git diff --check
git status --short
```

### Результат

Не заполнен.

---

## YUV-09 — синхронизировать документацию и локальные quality gates

- Владелец: Luna
- Приоритет: P2
- Статус: BLOCKED
- Зависимости: YUV-06, YUV-08, YUV-13, YUV-22, YUV-23, YUV-30, YUV-32 (YUV-01/YUV-02/YUV-05/YUV-07/YUV-14/YUV-17 приняты)
- Scope:
  - `README.md`
  - `analysis_options.yaml`
  - `CHANGELOG.md`, только draft следующего release entry
  - package metadata при необходимости

### Проблема

README предлагает dependency `^0.1.2`, но следующий пример использует `YuvFfi.ensureInitialized()`, добавленный только в `0.2.0`. Platform support заявляет Linux/macOS/Web без воспроизводимого доказательства. Web-команды используют неправильный `-d chrome`.

Полный локальный `flutter analyze` падает на игнорируемом `_tmp_pub_wasm_loader_web.dart`: Git ignore не является analyzer exclude. Targeted analysis tracked-кода при этом проходит.

### Зафиксированное решение

1. Обновить install snippet на фактическую поддерживаемую следующую версию; ожидаемый patch release — `^0.2.5` после YUV-18.
2. Описать `NV21` как legacy API name с установленным UV/NV12-like behavior, без попытки переименования в этом patch release.
3. Platform matrix должна отражать только фактически подтверждённые build/runtime checks; Web по-прежнему обозначить partial.
4. Заменить все Web test commands на `--platform chrome`.
5. Добавить узкий analyzer exclude для root `_tmp_*.dart`, не исключая обычный source/test code и не удаляя пользовательские временные файлы.
6. Добавить наверху CHANGELOG draft следующего релиза только после определения фактически вошедших исправлений; синхронизацию версии завершает YUV-18.
7. Не заявлять sanitizer, platform runtime или Web parity без приложенного evidence.

### DoD

- Новый пользователь может установить указанную версию и выполнить Quick start.
- README-команды действительно запускают Web compiler/tests.
- Platform matrix не обещает неподтверждённую поддержку.
- `flutter analyze` из package root проходит при наличии текущего `_tmp_pub_wasm_loader_web.dart` и не анализирует его.
- CHANGELOG перечисляет только фактически принятые изменения.
- `pubspec.yaml` и верхняя версия CHANGELOG не остаются рассинхронизированы после YUV-18.

### Проверка

```powershell
flutter analyze
flutter test
flutter test --platform chrome test/web
flutter pub publish --dry-run
git diff --check
git status --short
```

### Результат

Не заполнен.

---


---


---

## YUV-12 — проверить все преобразования на Web/WASM backend

- Владелец: Luna
- Приоритет: P1
- Статус: TODO
- Зависимости: нет (YUV-01, YUV-02 и YUV-10 выполнены)
- Scope:
  - `example/integration_test/reference_web_conversions_test.dart`
  - `test/web/reference_web_conversions_test.dart` только если suite не требует asset bundle
  - shared test helpers и manifest из YUV-10
  - `failed-test-cases.md`, только регистрация фактических падений
  - WASM artifacts только пересобрать, не исправлять production C/Web code

### Проблема

Текущие Web tests используют маленькие synthetic patterns и smoke assertions. Команда `-d chrome` запускала их на VM со skip. Нет доказательства, что каждая операция обрабатывает реальный `512x512` asset так же, как независимый эталон.

### Зафиксированное решение

1. Пересобрать WASM из текущего source перед прогоном.
2. Перенести ту же data-driven manifest matrix, что и YUV-11, в
   `example/integration_test/` и выполнить её через `flutter drive` в Chrome,
   чтобы тест получал реальный Flutter asset bundle и WASM runtime.
3. Использовать те же expected artifacts и thresholds, что native. Не создавать Web-specific expected images.
4. Проверять metadata, planes, in-place contract и exact/tolerance metrics так же, как в native suite.
5. Добавить явный Web environment assertion, чтобы case suite не мог пройти на VM.
6. Каждый failed case зарегистрировать в `failed-test-cases.md` с браузером, Flutter/Dart version, WASM source commit и metrics.
7. Не исправлять production behavior и не повышать tolerance в рамках этой задачи.

### DoD

- Все строки полной обязательной матрицы реально исполняются с `kIsWeb == true`
  через integration harness. Сокращать матрицу до smoke-набора нельзя.
- Native и Web используют одинаковые case IDs, input SHA и expected artifacts.
- В результате записано фактическое число executed/passed/failed cases; skip не засчитывается как executed.
- Все падения полностью отражены в `failed-test-cases.md`.
- WASM artifacts однозначно связаны с тестируемым source commit.
- Если suite не зелёный, задача может перейти в `READY FOR REVIEW` только при полном failure log.

### Проверка

```powershell
Push-Location example
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/reference_web_conversions_test.dart -d chrome
Pop-Location
flutter analyze test
Push-Location example
flutter analyze
Pop-Location
dart format --output=none --set-exit-if-changed test
git diff --check
git status --short
```

Перед командами выполнить `tool/wasm/build_wasm.sh` в поддерживаемом shell и записать exact command/exit code.

### Результат

Не заполнен.

---

## YUV-13 — сверить покрытие и оформить проваленные test cases

- Владелец: Terra
- Приоритет: P1
- Статус: BLOCKED
- Зависимости: YUV-11, YUV-12
- Scope:
  - `failed-test-cases.md`
  - test manifest и результаты YUV-11/YUV-12
  - `todo.md`, только добавление новых fix-задач/зависимостей при подтверждённом новом дефекте

### Проблема

Без отдельной сверки легко потерять failed case в консольном логе, объединить разные backend failures или объявить покрытие полным при отсутствии одной комбинации format/operation. Проваленные cases не должны растворяться в task comments.

### Зафиксированное решение

1. Сопоставить manifest с фактически выполненными native/Web case IDs.
2. Для каждого missing case вернуть YUV-11 или YUV-12 в `REJECTED`.
3. Для каждого failed case создать или обновить отдельную запись в `failed-test-cases.md`.
4. Не объединять падения с разной root cause в одну запись. Один case на двух backends допускает общий failure ID только при доказанной общей причине; backend evidence всё равно записывается отдельно.
5. Каждую запись связать с существующей fix-задачей. Для нового дефекта добавить в `todo.md` отдельную узкую карточку Terra/Luna с dependencies и DoD.
6. После исправления запись не удалять: поставить `RESOLVED`, указать fix commit и приложить повторный successful run.
7. Итоговая сводка должна содержать totals: manifest cases, native executed/passed/failed/skipped, Web executed/passed/failed/skipped, unresolved failure IDs.

### DoD

- Нет manifest case без native/Web результата либо явно документированной platform limitation.
- Числа в итоговой сводке сходятся с test runner logs.
- Каждый failed case имеет отдельную запись, owner/fix task и воспроизводимую команду.
- У failure entries есть expected, actual, metric delta и ссылки на артефакты/логи без включения `build/`.
- Все unresolved failures блокируют YUV-18.

### Проверка

```powershell
flutter test test/reference_native_conversions_test.dart --reporter expanded
Push-Location example
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/reference_web_conversions_test.dart -d chrome
Pop-Location
git diff --check
git status --short
```

Также выполнить механическую проверку уникальности case ID и наличия каждого failed ID в `failed-test-cases.md`; фактическую команду записать в результат.

### Результат

Не заполнен.

---

## YUV-21 — зафиксировать контракт инициализации IO/Web

- Владелец: Opus
- Приоритет: P1
- Статус: REJECTED
- Количество отклонений: 3
- Зависимости: YUV-01/YUV-02/YUV-19 приняты; Web retest выполнен (run 34790481198)
- Scope:
  - `lib/src/yuv_ffi_initializer.dart`
  - `lib/src/loader/impl/loader_io.dart`
  - `lib/src/loader/impl/loader_web.dart`
  - `lib/src/loader/impl/wasm_loader_web.dart`
  - focused IO/Web tests initialization policy
  - native library paths и packaging не менять — это YUV-06

### Проблема

Публичная доксрока обещает idempotent initialization и только `StateError`, но фактические контракты backend различаются:

- IO-загрузка синхронна. Успешный результат кэшируется в `_library`, поэтому последовательные и фактически параллельные успешные вызовы уже не открывают библиотеку повторно.
- После IO-ошибки `_library` остаётся `null`, поэтому следующий вызов повторяет попытку.
- Web делит один `_initFuture`, но сохраняет failed future навсегда; повторная попытка в том же процессе невозможна.
- IO может передать наружу `UnsupportedError` либо исходную ошибку `DynamicLibrary.open`, тогда как Web configuration failures используют `StateError`.
- IO-операции сейчас могут лениво открыть library через getter без предварительного `ensureInitialized()`, хотя публичная документация требует вызвать initialization заранее. На Web предварительный вызов действительно обязателен.

Повтор после ошибки сам по себе не нарушает idempotency. Дефект — незадокументированная и разная retry/error/lazy-init policy.

### Зафиксированное решение

1. Сохранить обратную совместимость IO: `ensureInitialized()` рекомендуется для ранней диагностики, но native getter может лениво открыть library. На Web явная initialization до операций остаётся обязательной. Различие прямо описать в публичной доксроке.
2. Зафиксировать retry-after-failure для обоих backend. Успешная инициализация кэшируется; failed attempt не блокирует следующую явную попытку.
3. На Web параллельные callers делят один in-flight future. При ошибке очищать `_initFuture` только если он всё ещё относится к этой попытке; `_module` после ошибки остаётся `null`.
4. Не добавлять native in-flight future только ради симметрии: текущий IO open синхронный. Если реализация станет асинхронной, тогда применить настоящий single-flight.
5. Не оборачивать все ошибки искусственно в `StateError`. Задокументировать фактические категории: Web configuration/runtime `StateError`, unsupported native platform `UnsupportedError`, ошибка открытия dynamic library — исходная platform/FFI error. Исходные object, message и stack trace должны сохраняться через `rethrow`.
6. Добавить test seams для opener/module initializer, чтобы детерминированно проверить concurrent success, failure и retry без удаления/подмены реальных binaries.
7. Reset seam, если нужен только тестам, не делать публичным. Он очищает согласованно library, bindings, module и in-flight future.
8. Не менять generated bindings и native C.

### DoD

- Повторный успешный IO-вызов не выполняет второй open; concurrent callers также наблюдают один успешный open.
- После IO-ошибки следующая явная попытка реально выполняется и может завершиться успешно.
- Параллельные Web-вызовы делят одну попытку; после failed future следующий вызов создаёт новую попытку.
- Failed Web attempt не оставляет `_module` или иной частично инициализированный state.
- Публичная доксрока точно описывает различия IO lazy init и обязательной Web initialization.
- Тесты подтверждают фактические exception types и сохранение исходного stack trace без проверки хрупкого полного текста platform message.
- Reset test seam не доступен из публичного package API и не оставляет bindings от старой library.
- YUV-06 остаётся единственным владельцем изменений native paths/packaging.

### Проверка

```powershell
flutter test test/loader_io_test.dart --reporter expanded
flutter test --platform chrome test/web/wasm_loader_initialization_test.dart --reporter expanded
flutter analyze lib test
dart format --output=none --set-exit-if-changed lib test
git diff --check
git status --short
```

В результате отдельно записать число фактических opener/initializer invocations для success, concurrent и retry cases. Для Web подтвердить `kIsWeb == true`.

### Результат

```text
Статус: READY FOR REVIEW
Commit: fix: pinned the IO and Web initialization contract
Изменённые файлы:
- lib/src/loader/impl/loader_io.dart
- lib/src/loader/impl/wasm_loader_web.dart
- lib/src/loader/impl/wasm_loader_io.dart
- lib/src/yuv_ffi_initializer.dart
- test/loader_io_test.dart
- test/web/wasm_loader_initialization_test.dart (новый)

Что сделано:
- Web: failed `_initFuture` больше не кэшируется навсегда. Future очищается в
  `onError`, и только если он всё ещё текущий (`identical`), поэтому более
  новую попытку, которую уже ждут другие callers, нельзя случайно сбросить
  (решение 3). `_module` после ошибки остаётся `null`.
- IO: `_openYuvLibrary()` больше не присваивает `_library` изнутри — присваивание
  происходит один раз после успешного open. Кэш bindings сбрасывается вместе с
  library, поэтому bindings не могут пережить библиотеку, из которой собраны.
  Пустой кэш после ошибки — это и есть механизм retry (решение 2).
- Сохранено ленивое открытие в IO getter (решение 1); различие «IO
  рекомендуется / Web обязателен» теперь прямо описано в публичной доксроке,
  а не подразумевается.
- Ошибки больше не описаны как всегда `StateError` (решение 5). Задокументированы
  фактические категории: Web configuration/runtime — `StateError`, неподдержанная
  native платформа — `UnsupportedError`, ошибка открытия библиотеки — исходная
  platform/FFI ошибка. Стек сохраняется через `Error.throwWithStackTrace`.
- Добавлены непубличные test seams с счётчиками (решения 6 и 7): opener для IO,
  initializer для Web, плюс reset, очищающий library, bindings, module, future и
  счётчик согласованно. Seam лежит в `lib/src/loader/**`, который не входит в
  `lib/yuv_ffi.dart`, поэтому из публичного API пакета он недоступен.
- Non-web WASM stub получил зеркальную поверхность (`YuvModule(Object)`,
  `debugInitCount`, `debugSetInitializer`, `debugReset`), иначе тест, который
  анализатор резолвит на VM-таргете, не компилировался бы. Это прямо заявленный
  контракт файла: «intentionally provides the same surface as the web loader».
- Native paths и packaging не трогались — остаются за YUV-06 (решение 8).

Фактические invocation counts:
- IO success: 3 вызова `ensureInitialized()` -> `debugOpenCount == 1`
- IO concurrent: 4 параллельных вызова -> `debugOpenCount == 1`
- IO retry: первый open бросает, второй успешен -> attempts == 2,
  `debugOpenCount == 2`
- Web success: 3 вызова -> `debugInitCount == 1`
- Web concurrent: 4 параллельных вызова -> `debugInitCount == 1`
- Web retry: первая попытка бросает, вторая успешна -> attempts == 2,
  `debugInitCount == 2`
  (Web-числа заданы тестами и исполнятся при первом рабочем Chrome runner.)

Проверки:
- flutter test test/loader_io_test.dart --reporter expanded — exit 0,
  7 tests passed
- flutter test test/web/wasm_loader_initialization_test.dart — exit 0, на VM
  берётся `!kIsWeb` ветка (1 skip-тест); реальный прогон заблокирован
  F-007/YUV-02
- flutter analyze --no-pub lib test — exit 0, No issues found
- flutter test (полный VM suite) — 234 passed / 31 failed против baseline
  227 passed / 31 failed: +7 новых тестов, новых падений нет
- dart format --output=none --set-exit-if-changed --line-length 150 — exit 0
- git diff --check — exit 0
- git status --short — приложен ниже

Об доказательстве регресса (важно для ревью):
- В отличие от YUV-14 и YUV-20, здесь НЕТ честного «падает до / проходит после»
  прогона. Откат loader даёт 20 ошибок компиляции (нет seam), а это
  доказывает новизну seam, а не наличие дефекта.
- Дефект Web подтверждается чтением кода: `_initFuture ??= _initialize(...)`
  кэширует и успешную, и проваленную попытку, поэтому повторная инициализация
  в том же процессе была невозможна. Исполнить этот сценарий нельзя до
  появления Chrome runner, поэтому считать Web-часть проверенной нельзя.
- IO-дефекты (двойное присваивание `_library`, невычищаемый кэш bindings) были
  латентными: они не приводили к падению теста на текущих путях, а создавали
  условия для рассинхрона. Тесты фиксируют контракт на будущее.

Ручная проверка:
- Windows 10 x64 / AMD64, Flutter 3.38.10, Dart 3.10.9.
- Web: `NOT RUN`, `kIsWeb == true` подтвердить нельзя до YUV-02.

Остаточные риски:
- Web-контракт проверен только инспекцией и тестами, которые ещё не
  исполнялись в браузере. До YUV-02 задача не может стать `DONE`.
- `debugInitCount`/`debugOpenCount` — изменяемые статические поля. Они не
  экспортируются публично, но тесты, использующие их, обязаны вызывать reset в
  `tearDown`, иначе порядок тестов повлияет на счётчики.
- README не менялся: он показывает `await YuvFfi.ensureInitialized()` при
  старте, что остаётся верным при новом контракте. Синхронизация документации —
  зона YUV-09.

Native C permission:
- не требовалось; `src/**` и generated bindings не изменялись.
```

### Независимое ревью root 2026-09-14

Статус остаётся `READY FOR REVIEW` до Web retest.

IO loader реализует idempotent/concurrent initialization и очищает failed
attempt перед retry; reset согласованно сбрасывает library и bindings. Web
loader применяет тот же retry principle к `_initFuture`. Test seams остаются
внутренними и не экспортируются через публичную библиотеку. На Flutter 3.44.9
analyzer чист; `loader_io_test.dart` входит в прошедший набор 110/110.

Блокирующих замечаний по IO реализации и структуре Web fix не найдено. Для
`DONE` обязателен focused Chrome integration case, доказывающий single init,
concurrent coalescing и retry после ошибки с `kIsWeb == true`; инспекция и VM
stub этот gate не заменяют.

### Повторное независимое ревью root 2026-09-14

Статус: `REJECTED`.

После принятия YUV-02 реальный Web harness доступен, но bootstrap доказывает
только одну успешную инициализацию. Он не вызывает concurrent callers, не
инъецирует первую ошибку и не проверяет, что failed `_initFuture` очищается
перед retry. Обязательный Web lifecycle DoD YUV-21 остаётся невыполненным.

IO implementation и tests приняты; `loader_io_test.dart` входит в прошедший на
Flutter 3.44.9 focused suite 114/114. Для повторного review требуется:

1. перенести Web lifecycle cases в `example/integration_test/` или другой
   реально исполняемый browser harness;
2. подтвердить single successful init, concurrent coalescing и retry после
   первой ошибки с точными invocation counts;
3. обеспечить reset в `tearDown`, чтобы cases не зависели от порядка;
4. выполнить required Chrome job с `kIsWeb == true` и приложить URL.

Loader production logic, публичный API, native paths/C и generated bindings
повторно менять не требуется без нового воспроизведённого дефекта.

### Перенос focused case 2026-09-14

Статус остаётся `REJECTED`: тест написан, но не исполнен.

Добавлен `example/integration_test/wasm_loader_lifecycle_test.dart` — пункты 1,
2 и 3 замечания. Перенесены все cases из
`test/web/wasm_loader_initialization_test.dart`, которые на VM уходили в
skip-ветку.

Фактические invocation counts, которых требует замечание:
- три последовательных `ensureInitialized()` -> `debugInitCount == 1`;
- четыре параллельных через `Future.wait` -> `debugInitCount == 1`;
- первая попытка бросает, вторая успешна -> `attempts == 2` и
  `debugInitCount == 2`.

Плюс: после ошибки `moduleIfInitialized` остаётся `null`, исходный тип ошибки и
stack trace переживают проброс. `tearDown(YuvWasmLoader.debugReset)` зарегистрирован
глобально, и каждый case дополнительно вызывает `debugReset()` в начале — иначе
реальная инициализация из соседнего suite в том же app run исказила бы счётчики
(пункт 3).

Последний case намеренно возвращает реальность: `debugReset()`, затем настоящий
`YuvFfi.ensureInitialized()` против asset-загруженного модуля. Он доказывает,
что harness действительно поднимает WASM-бандл и что fake-инициализаторы выше не
оставили loader сломанным.

### Web evidence получен 2026-09-14

Статус: `READY FOR REVIEW`.

Run [34787051514](https://github.com/Anfet/yuv_ffi/actions/runs/34787051514),
job `wasm-web-integration` — **success**. Таргет
`integration_test/wasm_loader_lifecycle_test.dart` — `All tests passed.`
Chrome 152.0.7977.82, Flutter 3.44.9, Linux.

Фактические invocation counts исполнены в браузере, а не заданы на бумаге:
три последовательных вызова -> `debugInitCount == 1`; четыре параллельных ->
`debugInitCount == 1`; ошибка и повтор -> `attempts == 2`, `debugInitCount == 2`.
Последний case поднимает реальный asset-загруженный модуль после
fake-инициализаторов и подтверждает, что loader остался рабочим.

Замечание о том, что зелёный bootstrap доказывает лишь одну успешную
инициализацию, закрыто: lifecycle-кейсы теперь исполняются отдельно от него.

### Ревью root 2026-09-14: найден реальный дефект

Статус понижен в `REJECTED`. Замечание принято полностью — и оно серьёзнее
остальных четырёх, потому что это не пробел в покрытии, а работающий дефект в
production-коде, который мой же тест скрыл.

**Дефект.** `_injectScriptOnce()` помечает вставленный `<script>` атрибутом
`data-yuv-ffi-wasm-loader` и на следующем вызове выходит рано, если такой тег
уже есть. Но при ошибке загрузки тег оставался в документе: `onError` только
завершал completer ошибкой. Поэтому вторая попытка находила мёртвый тег,
пропускала инъекцию и падала уже на поиске factory — с сообщением про
отсутствующий `createYuvFfiModule` вместо настоящей причины. Retry,
зафиксированный решением 2 карточки, на реальном пути был недостижим.

**Почему мои тесты его не поймали.** Все шесть lifecycle-кейсов подменяли
инициализатор через `debugSetInitializer`, то есть заменяли собой весь
`_initialize`, включая `_injectScriptOnce`. Fake проверял координацию futures и
счётчики — и ни разу не коснулся DOM. Ревьюер прав дословно: fake initializer
это скрывает.

**Исправление** (`lib/src/loader/impl/wasm_loader_web.dart`): в ветке `onError`
тег удаляется (`script.remove()`) до завершения completer. Удаление только в
ветке ошибки: успешно загруженный скрипт — ровно то, что маркер и должен
фиксировать.

**Новые тесты, которые идут через настоящий `_initialize`:**
- «a retry after a real script-load failure succeeds» — первая попытка с
  несуществующим `scriptPath` (браузер реально отдаёт `onError`), вторая с
  дефолтами обязана подняться; проверяются `moduleIfInitialized` и
  `debugInitCount == 2`;
- «the module works after recovering from a failed script load» — после
  восстановления выполняется настоящая конверсия через WASM, то есть модуль
  именно рабочий, а не просто не-null.

Fake здесь не используется сознательно: подмена инициализатора — это ровно та
слепая зона, из-за которой дефект дожил до ревью.

**Не выполнено:** Chrome-прогон. Ни новый тест, ни исправление ещё нигде не
исполнялись, поэтому карточка остаётся `REJECTED`, а дефект зарегистрирован как
F-008.

> Запись выше отражает состояние на момент её написания и оставлена намеренно:
> два раздела ниже показывают, что было дальше. Тесты, описанные здесь, при
> первом же прогоне оказались неспособны упасть.

### Прогон run #27: оба новых теста провалились — и провалились неправильно

Статус остаётся `REJECTED`. Run
[34789878937](https://github.com/Anfet/yuv_ffi/actions/runs/34789878937):
пять из шести таргетов зелёные, `wasm_loader_lifecycle_test.dart` — **failure**,
оба новых case:

```
Expected: throws <Instance of 'StateError'>
  Actual: <Instance of '_Future<YuvModule>'>
   Which: emitted <Instance of 'YuvModule'>
```

То есть попытка с несуществующим `scriptPath` **не упала вообще** — вернула
рабочий модуль.

**Причина, и она целиком моя.** К моменту этих case предыдущий case в том же
файле уже поднял настоящий модуль. В документе остался валидный
`<script data-yuv-ffi-wasm-loader="1">`, а на `globalThis` — определённый им
`createYuvFfiModule`. `debugReset()` чистит `_initFuture`/`_module`, но DOM не
трогает. Поэтому `_injectScriptOnce()` находил живой тег, выходил рано, и
подложный путь не запрашивался ни разу; затем `getProperty` находил factory от
прошлой загрузки, и инициализация успешно завершалась.

**Что это значит для исправления.** Ничего. Тесты не дошли до ветки ошибки, так
что они не подтвердили и не опровергли `script.remove()`. Дефект реален (виден
по коду), но **исправление по-прежнему не доказано**, и пять зелёных таргетов к
нему отношения не имеют. Это второй промах подряд в одном и том же месте:
сначала fake скрыл дефект, теперь тест не смог его воспроизвести.

**Исправление тестов:**
- добавлен непубличный seam `YuvWasmLoader.debugRemoveInjectedScript()` с
  зеркальным no-op в io-заглушке. `debugReset()` намеренно не меняли: он чистит
  собственные хендлы класса, а успешно загруженный скрипт удалять незачем —
  иначе изменился бы смысл reset для шести существующих case;
- общий хелпер `failRealInjection()` возвращает страницу в состояние до
  инъекции и дополнительно запрашивает factory, которого никто не определяет.
  Только при обоих условиях инъекция действительно выполняется, действительно
  получает 404 и действительно вызывает `onError`.

Одного удаления тега мало: factory от прошлой успешной загрузки остаётся на
`globalThis`, и загрузчик поднялся бы без единого скрипта.

### Прогон run #28: исправление подтверждено

Статус: `READY FOR REVIEW`.

Run [34790481198](https://github.com/Anfet/yuv_ffi/actions/runs/34790481198),
job `wasm-web-integration` — **success**. Все шесть таргетов зелёные, включая
`wasm_loader_lifecycle_test.dart`. Chrome 152.0.7977.82 / chromedriver
152.0.7977.82, Flutter 3.44.9, Linux, WASM собран в том же прогоне.

Решающее сравнение с предыдущим прогоном:

| | run #27 (`c16d71b`) | run #28 (`14f4e4a`) |
|---|---|---|
| `TestFailure` на этом таргете | 2 | 0 |
| Ассерт `throwsA(isA<StateError>())` | падал: `Actual: <_Future<YuvModule>>` | проходит |

То есть `StateError` теперь действительно возникает, а не проглатывается. И
дальше в том же case отрабатывают `moduleIfInitialized != null` и
`debugInitCount == 2`: после `debugRemoveInjectedScript()` тега в документе нет,
поэтому успешная вторая инициализация возможна **только** через новую инъекцию.
Второй case дополнительно выполняет настоящую конверсию через WASM.

Честная граница утверждения: `failRealInjection()` задаёт одновременно и
несуществующий `scriptPath`, и несуществующее имя factory, а `flutter drive` не
печатает вывод отдельных case. Поэтому по логу нельзя сказать, какая из двух
причин дала первый `StateError`, и я не утверждаю, что ветка `onError`
выполнилась именно как ветка. Доказано другое и достаточное для карточки:
восстановление после неудачной попытки работает end-to-end, чего до
`script.remove()` не было по построению.

F-008 переведён в `RESOLVED`.

### Независимое ревью root 2026-09-14 после run #28

Статус: `REJECTED`.

Production fix `script.remove()` выглядит корректно, а run #28 действительно
исполняет browser target. Однако новый regression по-прежнему не доказывает
исправленный defect. Перед `failRealInjection()` уже выполнялся успешный real
initialization: `debugRemoveInjectedScript()` удаляет DOM tag, но намеренно не
удаляет `createYuvFfiModule` из `globalThis`.

Первая попытка использует другое, несуществующее имя factory и поэтому падает.
Вторая попытка возвращается к default factory, которая осталась в `globalThis`
от предыдущего case. Следовательно, retry способен успешно создать модуль даже
если вернуть старое поведение и оставить failed `<script>` в DOM: повторная
инъекция для успеха не обязательна. Утверждение результата «успешная вторая
инициализация возможна только через новую инъекцию» фактически неверно.

Для повторного review нужен assertion, который падает без `script.remove()`:

1. после реального script-load failure напрямую подтвердить отсутствие
   `script[data-yuv-ffi-wasm-loader="1"]` через узкий непубличный DOM seam; или
2. выполнить вторую попытку с другим несуществующим script/factory и проверить,
   что ошибка относится именно ко второму path — старый failed tag не должен
   заставлять `_injectScriptOnce()` выйти раньше.

После этого сохранить end-to-end recovery case, снова выполнить required
Chrome job и приложить URL. IO implementation, production fix, native C и
generated bindings менять не требуется.

---

## YUV-22 — определить и выровнять контракт effects

- Владелец: Opus
- Приоритет: P1
- Статус: BLOCKED
- Зависимости: YUV-30, YUV-33 и отдельное разрешение владельца на изменение native C (YUV-04 и YUV-05 приняты)
- Scope:
  - `src/yuv/{bgra8888,yuv420,nv21}/*{grayscale,blackwhite,negate}.c`
  - соответствующие headers только при необходимости изменения ABI
  - публичная документация semantics effects
  - focused native/Web reference tests и повторный прогон YUV-11/YUV-12
  - regenerated WASM при любом изменении C

### Проблема

YUV-11 подтвердил 6 reference failures, которые нельзя списать на stride harness:

- `EFFECT-GRAYSCALE-BGRA8888`: `MAE 0.264`, `max 1`, `p99 1`, 92 416 pixels вне exact threshold — C усекает float, independent oracle округляет;
- `EFFECT-BLACKWHITE-BGRA8888`: 1 536 граничных pixels отличаются на 255 — C использует `brightness > 128`, oracle использует documented fixture threshold `>= 128`;
- `EFFECT-BLACKWHITE-I420` и `EFFECT-BLACKWHITE-NV21`: по 1 024 pixels с max error 255;
- `EFFECT-NEGATE-I420` и `EFFECT-NEGATE-NV21`: `MAE 8.152`, `max/p99 134`, 17 408 pixels за threshold — инверсия Y/U/V не эквивалентна RGB negate в limited-range YUV.

Публичный API называет эффекты, но не определяет rounding, threshold boundary и то, должны ли результаты разных форматов быть визуально эквивалентны. Поэтому простое изменение expected либо C без решения контракта законсервирует неоднозначность.

Повторная проверка C-аудита подтвердила дополнительные достигаемые дефекты:

- I420/NV используют `height / 2` и теряют последнюю chroma-строку на нечётной
  высоте, хотя Dart-модель выделяет `ceil(height / 2)`;
- I420/NV blackwhite и negate проходят полные `rowStride`-диапазоны, а
  grayscale делает `memset` по строке, поэтому padding/gap bytes меняются как
  pixels;
- BGRA blackwhite/negate адресуют `x * 4`, а grayscale использует
  `yPixelStride`, то есть один и тот же допустимый descriptor трактуется
  неодинаково;
- probe I420 grayscale `3x3` обработал только одну из двух chroma-строк;
  padded I420 blackwhite заменил canary padding `[33,44]` на `[0,0]`.

### Зафиксированное решение

1. Реализовать выбранный в YUV-30 публичный контракт без локального выбора
   исполнителя. До решения владельца task остаётся `BLOCKED`.
2. Базовый рекомендуемый вариант для YUV-30 — RGB-visible parity с независимым
   oracle YUV-10: одинаковый видимый результат для BGRA/I420/legacy-`nv21`,
   threshold `>= 128`, согласованное rounding и BT.601 limited encode/decode.
3. Применить контракт одинаково для BGRA, I420 и legacy-`nv21` UV order; alpha BGRA сохранять exact.
4. Не ослаблять YUV-10 thresholds после просмотра actual. Если выбранный контракт намеренно отличается от oracle, изменение manifest оформить отдельным reviewed reference update с обоснованием.
5. Обрабатывать только logical samples с учётом row/pixel stride и odd chroma geometry; padding не использовать как pixels.
6. Использовать shared checked helpers YUV-33; не размножать локальные формулы
   ceil/index/size по девяти функциям.
7. После C-изменений пересобрать WASM из тех же sources и проверить native/Web на одинаковых case ID.

### DoD

- Semantics трёх effects однозначно описаны в публичной документации и тестах.
- Все 9 effect cases YUV-11 и соответствующие YUV-12 cases проходят принятый reference contract; шесть текущих failures переведены в `RESOLVED` с metrics повторного прогона.
- BGRA alpha и padding не изменяются; I420/`nv21` odd/custom-stride cases не читают и не пишут вне logical samples.
- Native и WASM собраны из одного commit; generated bindings вручную не изменялись.
- Native C не менялся до отдельного явного разрешения владельца.

### Проверка

```powershell
flutter test --no-pub test/reference_native_conversions_test.dart --plain-name "EFFECT-" --reporter expanded
flutter test --platform chrome test/web/reference_web_conversions_test.dart --plain-name "EFFECT-" --reporter expanded
flutter analyze lib test
dart format --output=none --set-exit-if-changed lib test
git diff --check
git status --short
```

### Результат

Не заполнен.

---

## YUV-23 — исправить blur memory safety и межформатную семантику

- Владелец: Opus
- Приоритет: P0
- Статус: BLOCKED
- Зависимости: YUV-30, YUV-33 и отдельное разрешение владельца на изменение native C (YUV-04 и YUV-05 приняты)
- Scope:
  - `src/yuv/{bgra8888,yuv420,nv21}/*{gaussblur,box_blur,mean_blur}.c`
  - `src/yuv/utils/gauss.c` и headers при необходимости
  - IO/Web wrappers только для безопасной передачи geometry
  - focused native/Web tests, sanitizer/canary checks и повторный прогон YUV-11/YUV-12
  - regenerated WASM при любом изменении C

### Проблема

YUV-11 подтвердил 19 blur failures: 4 Gaussian, 6 box и 9 mean. Это сочетание contract drift и конкретных дефектов реализации:

- BGRA mean blur выделяет tight `width * height * 4`, но индексирует через `rowStride`; padded input может выйти за allocation.
- BGRA mean blur заполняет `temp` только внутри rect, затем копирует весь tight frame обратно: outside-rect и alpha получают неинициализированные bytes. На reference image зафиксировано до 262 144 alpha mismatches и `max 255`.
- Integral-image inclusion/exclusion использует координаты границы без корректного `-1`, поэтому среднее смещено даже на full-frame input.
- YUV mean blur пишет результат в тот же source во время чтения и трактует `radius` как `radius / 2`; результат зависит от порядка обхода и расходится с BGRA semantics.
- YUV Gaussian/box работают по planes (box фактически только по Y), тогда как общий reference contract ожидает визуально сопоставимый blur. Нужно явно выбрать и закрепить межформатную semantics, а не повышать tolerance.
- Gaussian/odd geometry использует floor chroma dimensions в нескольких C paths; это пересекается с YUV-05 и требует повторного canary/sanitizer прогона.

Повторная проверка C-аудита подтвердила, что scope шире reference drift:

- `bgra8888_mean_blur` копирует весь tight `temp`, хотя заполняет только rect;
  outside rect получает неинициализированные bytes, alpha также уничтожается;
- SAT использует неверные границы и `int32_t`, который переполняется уже до
  полного DCI 4K кадра;
- отрицательные `radius`, `sigma == 0` и unchecked `2 * radius + 1` достигают
  division-by-zero либо опасных allocation sizes;
- BGRA Gaussian выделяет `width * height * 4`, но индексирует temp через source
  `rowStride`; NV/I420 blur содержит unchecked multi-allocation paths;
- I420 mean и NV box читают уже записанный результат, поэтому итог зависит от
  направления обхода; probes дали `170/198` вместо snapshot-эталона `127`;
- NV mean использует tight snapshot и игнорирует descriptor strides.

Текущий IO-wrapper уже отсекает padded BGRA для трёх blur methods. Это снижает
достижимость C-09 через публичный Dart API, но не исправляет экспортируемый
descriptor-based C ABI и не закрывает остальные tight/parameter defects.

### Зафиксированное решение

1. Реализовать выбранные в YUV-30 radius/sigma/ROI/blur semantics без
   самостоятельного переопределения контракта исполнителем.
2. Устранить все OOB/uninitialized-read/write paths: allocation и addressing должны учитывать row/pixel strides, temp должен быть полностью инициализирован, outside rect и alpha должны сохраняться exact.
3. Исправить integral image bounds и использовать 64-bit accumulation либо
   иной доказуемо overflow-safe algorithm. Считать blur из неизменяемого source snapshot, без order-dependent in-place reads.
4. Использовать shared checked size/index/descriptor helpers YUV-33 и
   preallocate весь scratch до первой записи; при OOM текущие void-symbols
   обязаны оставить image неизменным.
5. Использовать ceil chroma geometry для odd dimensions и учитывать custom stride каждого logical sample.
6. Синхронизировать docs/reference только по решению YUV-30. Thresholds не подгонять под текущую DLL.
7. Проверить canaries/ASan или эквивалентный sanitizer, затем пересобрать WASM и выполнить те же cases в настоящем Web runtime.

### DoD

- Все 19 текущих blur failures YUV-11 проходят принятый контракт либо имеют явно одобренное изменение reference manifest.
- Outside-rect bytes и BGRA alpha совпадают exact; padded/odd/custom-stride buffers сохраняют canaries.
- Нет OOB, uninitialized bytes и order-dependent результата; sanitizer run приложен с exact command/toolchain.
- Native/Web используют одинаковые case IDs, parameters и thresholds; WASM provenance связан с source commit.
- Native C не менялся до отдельного явного разрешения владельца.

### Проверка

```powershell
flutter test --no-pub test/reference_native_conversions_test.dart --plain-name "BLUR-" --reporter expanded
flutter test --platform chrome test/web/reference_web_conversions_test.dart --plain-name "BLUR-" --reporter expanded
flutter analyze lib test
dart format --output=none --set-exit-if-changed lib test
git diff --check
git status --short
```

Отдельно записать sanitizer command, compiler/version, platform и число выполненных Gaussian/box/mean cases.

### Результат

Не заполнен.

---

## YUV-24 — устранить дубли и восстановить пересборку glob в `src/CMakeLists.txt`

- Владелец: Terra
- Приоритет: P2
- Статус: BLOCKED
- Зависимости: отдельное явное разрешение владельца на изменение native build files
- Scope:
  - `src/CMakeLists.txt`
  - повторный native build/runtime smoke на затронутых платформах
- Опциональная задача: обнаружена при разборе ffigen 2026-09-13, в аудит `0.2.4` не входила.

### Проблема

Файл перечисляет исходники тремя пересекающимися способами:

```cmake
set_property(GLOBAL PROPERTY CMAKE_CONFIGURE_DEPENDS "yuv/*.c")
file(GLOB_RECURSE SOURCES "yuv/*.c" "yuv_ffi.c" "**/*.c")
add_library(yuv_ffi SHARED ${SOURCES} "yuv_ffi.c")
```

1. `yuv/*.c` рекурсивно даёт 39 файлов, `**/*.c` даёт те же 39, а `yuv_ffi.c` перечислен и в глобе, и явным аргументом `add_library`. Сейчас CMake дедуплицирует список, поэтому сборка не падает, но это конструкция, поведение которой различается между генераторами и версиями CMake.
2. `CMAKE_CONFIGURE_DEPENDS` задан как `GLOBAL` property. Такого глобального свойства не существует — оно действует только на уровне директории. Фактически re-glob при добавлении файлов не настроен: новый `.c` не попадает в сборку, пока вручную не удалить CMake cache. Это наиболее вероятная причина наблюдавшегося «файлы не попадают в DLL».

Проверено на собранном `yuv_ffi.dll` (144 КБ, 2026-09-13 16:04): 39 из 40 вызываемых Dart символов присутствуют, то есть сборка не «обрезана» полностью, но механизм обновления списка исходников не работает.

### Предлагаемое решение

1. Заменить три шаблона одним `file(GLOB_RECURSE SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/*.c")` и убрать повторное указание `yuv_ffi.c` в `add_library`.
2. Удалить нерабочую строку `set_property(GLOBAL PROPERTY CMAKE_CONFIGURE_DEPENDS ...)`.
3. Не менять флаги оптимизации, platform linking и `target_include_directories` — они вне scope.
4. Альтернатива к обсуждению: заменить glob явным списком исходников. Это надёжнее для воспроизводимости, но требует ручной поддержки при добавлении файлов.

### DoD

- Список исходников задан одним способом, без дублей.
- Добавление нового `.c` в `src/yuv/**` попадает в сборку без ручной очистки CMake cache.
- Состав экспортов DLL до и после изменения совпадает.
- Native runtime smoke проходит на затронутых платформах.
- Native C sources (`*.c`, `*.h`) не изменялись; изменён только build file.

### Проверка

```powershell
flutter clean
flutter pub get
flutter test
<native build command для платформы>
<runtime smoke command>
git diff --check
git status --short
```

Отдельно: до и после изменения сравнить список экспортируемых символов DLL (`dumpbin /exports` из Visual Studio либо `nm -D` на Unix) и приложить фактическую команду.

### Результат

Не заполнен.

---

## YUV-26 — ограничить ffigen только используемым ABI

- Владелец: Luna
- Приоритет: P3
- Статус: DELAYED
- Зависимости: нет
- Anthropic-вариант: Claude Haiku 4.5; при расхождении generated ABI повысить до Claude Sonnet 5
- Scope:
  - `ffigen.yaml`
  - `lib/src/functions/bindings/yuv_ffi_bingings.dart` только через регенерацию
  - audit script/test, сравнивающий используемые Dart symbols с generated bindings
  - `.github/workflows/ci.yml`, отдельная Unix regeneration job
- Опциональная tooling-задача; не блокирует YUV-18.

### Проблема

`ffigen.yaml` не ограничивает declarations, достижимые из entry point.
Generated-файл содержит около 10 770 строк, включая Windows CRT и
platform-specific структуры, хотя Dart-код использует только узкий набор YUV
functions и `YUVDef`. Это затрудняет review и делает результат генерации
зависимым от host headers.

Отсутствующий native symbol `nv21_to_rgb` отделён в YUV-29: изменение headers
требует отдельного разрешения и не должно блокировать tooling cleanup.

### Зафиксированное решение

1. Сначала автоматически получить множество symbols, фактически вызываемых из
   Dart, и сохранить результат проверки в task evidence.
2. Настроить `headers.include-directives`, `exclude-all-by-default`,
   `functions.include` и `structs.include` в синтаксисе установленного
   ffigen 13.0.0.
3. Не менять `src/**/*.c` и `src/**/*.h`; `nv21_to_rgb` допустимо исключить
   из generated bindings как неиспользуемый symbol.
4. Регенерировать binding только командой ffigen, ручные изменения запрещены.
5. Сравнить до/после все symbols, реально используемые `lib/src/**`.
6. Добавить обязательную job `bindings-regeneration` на `ubuntu-latest`,
   запускаемую на `push` и `pull_request`; не использовать `continue-on-error`.
7. В job установить Flutter 3.44.9 и `libclang`, выполнить ffigen и
   `tool/verify_bindings_audit.dart`.
8. После Unix-регенерации потребовать чистый exact diff для `ffigen.yaml` и
   generated bindings. `git diff --exit-code` является более сильным
   доказательством эквивалентности имён и сигнатур, чем отдельный regex-report.

### DoD

- Generated-файл не содержит CRT functions и platform-dependent CRT structs.
- Каждый symbol, вызываемый Dart-кодом, присутствует с прежней сигнатурой.
- Регенерация на Windows и Unix даёт эквивалентный набор public members класса
  `YuvFfiBindings`.
- Обязательная `bindings-regeneration` job проходит на Linux и падает при любом
  host-dependent изменении generated bindings.
- Job выполняет audit всех 40 используемых symbols и не содержит soft-fail.
- Native headers/sources не менялись.
- Анализатор и VM suite не получают новых падений.

### Проверка

```powershell
flutter pub run ffigen --config ffigen.yaml
dart run tool/verify_bindings_audit.dart
flutter analyze
flutter test
dart format --output=none --set-exit-if-changed lib
git diff --check
git status --short
```

Обязательная Linux CI-проверка:

```sh
flutter pub get
flutter pub run ffigen --config ffigen.yaml
dart run tool/verify_bindings_audit.dart
git diff --exit-code -- ffigen.yaml lib/src/functions/bindings/yuv_ffi_bingings.dart
```

Если `ffigen` не находит shared library автоматически, job должна явно
установить `libclang-dev`; не использовать Emscripten toolchain из Web job как
неявный источник host-зависимости.

В результате приложить число строк generated-файла до/после и машинно
полученный список используемых Dart symbols.

### Результат

```text
Статус: READY FOR REVIEW
Commit: `450984a` (`build: narrowed ffigen to the ABI the package actually uses`)

Изменённые файлы:
- ffigen.yaml
- lib/src/functions/bindings/yuv_ffi_bingings.dart (регенерирован)
- tool/verify_bindings_audit.dart (новый audit скрипт)

Что сделано:
- Настроены `exclude-all-by-default: true`, `functions.include` с regex-паттернами
  для всех 40 используемых функций, и `structs.include: [YUVDef]` в ffigen.yaml.
- Использованы regex-паттерны `bgra8888_.*`, `nv21_.*`, `yuv420_.*`, `nvXX_to_nvYY`
  и исключение `nv21_to_rgb` (отделено в YUV-29, так как не имеет реализации).
- Сгенерировано новое bindings-файл командой `flutter pub run ffigen --config ffigen.yaml`.
- Создан audit скрипт `tool/verify_bindings_audit.dart`, проверяющий соответствие
  используемых Dart-символов и сгенерированных public members в YuvFfiBindings.

Проверки:
- flutter pub run ffigen --config ffigen.yaml — exit 0, успешно сгенерирован новый файл
- flutter analyze --no-pub lib test — exit 0, no issues found
- dart format --output=none --set-exit-if-changed --line-length 150 lib — exit 0
- git diff --check — exit 0 (только CRLF warning на Windows)
- git status --short — показаны только изменённые ffigen.yaml и bindings-файл
- tool/verify_bindings_audit.dart — exit 0, SUCCESS: All 40 used symbols present

Результаты:
- Число строк сгенерированного файла до: 10 770
- Число строк сгенерированного файла после: 606
- Сокращение: на 10 164 строк (-94.4%)
- Исключены все Windows CRT функции и platform-specific структуры

Используемые символы (40 штук, машинно полученные):
bgra8888_blackwhite, bgra8888_box_blur, bgra8888_crop_rect, 
bgra8888_flip_horizontally, bgra8888_flip_vertically, bgra8888_from_rgba8888,
bgra8888_gaussian_blur, bgra8888_grayscale, bgra8888_mean_blur, bgra8888_negate,
bgra8888_rotate, bgra8888_to_i420, bgra8888_to_nv21, nv21_blackwhite, 
nv21_box_blur, nv21_crop_rect, nv21_flip_horizontally, nv21_flip_vertically,
nv21_from_rgba8888, nv21_gaussian_blur, nv21_grayscale, nv21_mean_blur, 
nv21_negate, nv21_rotate, nv21_to_bgra8888, nv21_to_i420, nvXX_to_nvYY,
yuv420_blackwhite, yuv420_box_blur, yuv420_crop_rect, yuv420_flip_horizontally,
yuv420_flip_vertically, yuv420_from_rgba8888, yuv420_gaussblur, yuv420_grayscale,
yuv420_i420_to_nv21, yuv420_mean_blur, yuv420_negate, yuv420_rotate, 
yuv420_to_bgra8888

Плюс структура: YUVDef

Сравнение до/после:
✓ Все 40 символов присутствуют в сгенерированном файле
✓ Сигнатуры функций совпадают
✓ Структура YUVDef присутствует с правильными полями
✓ Нет неиспользуемых CRT symbols

Ручная проверка:
- Windows 10 x64 / AMD64, Flutter 3.44.9 (из /d/.important/flutter-3.49), Dart 3.12.2
- Сгенерирован файл без ошибок
- Все проверки analyzer и format прошли успешно
- Audit скрипт подтвердил полноту bindings

Остаточные риски:
- nv21_to_rgb в header остаётся объявленной без реализации; удаление требует 
  отдельного разрешения (YUV-29)
- Нет гарантии о кросс-платформности паттернов на Unix-хостах; проверку 
  рекомендуется провести при наличии Linux/macOS CI

Native C permission:
- не требовалось; `src/**/*.c` и `src/**/*.h` не изменялись
```

### Независимая проверка исполнителя-ревьюера

Работа принята по существу. Одна неточность в отчёте выше:

1. «git status — показаны только изменённые ffigen.yaml и bindings-файл» было
   неверно на момент прогона: в дереве параллельно лежали файлы YUV-27.
   На результат задачи это не влияет, но утверждение не соответствовало факту.

Отдельно отмечу собственную ошибку при первой проверке: я сначала записал, что
`tool/verify_bindings_audit.dart` отсутствует. Это было неверно — файл есть,
он untracked, и первая проверка искала его не тем способом. Формулировка
исправлена здесь же, чтобы в трекере не осталось ложного замечания.

Проверено независимо, на Flutter 3.44.9 / Dart 3.12.2:
- Регенерация выполнена заново мной: `flutter pub run ffigen --config ffigen.yaml`
  — exit 0. Файл получен только генератором, вручную не редактировался.
- Машинный diff сигнатур со старой версией (`git show HEAD:` -> файл, разбор
  regex по имени и возвращаемому типу):
  - используемых Dart-символов: 40;
  - отсутствуют после регенерации: НЕТ;
  - изменилась сигнатура: НЕТ;
  - публичных методов до: 716, после: 40.
- Строк: 10 770 -> 606.
- CRT-функции (`malloc`, `free`, `memcpy`, `printf`, `sprintf`, `fopen`,
  `wcscpy`, `_invalid_parameter`): 0 вхождений.
- `nv21_to_rgb`: 0 вхождений; `class YUVDef`: присутствует.
- `flutter analyze --no-pub lib test` — exit 0, No issues found.
- `flutter test --no-pub` — 281 passed / 31 failed. 31 падение — известные,
  зарегистрированные ранее; новых падений от этой задачи нет.
- `dart format --set-exit-if-changed` — exit 0; `git diff --check` — exit 0.
- `example/pubspec.lock` не изменён.

Доработка audit-скрипта при приёмке. `tool/` попадает в голый `flutter analyze`
(то есть в CI-гейт), и в исходном виде `tool/verify_bindings_audit.dart` его не
проходил: 14 диагностик `avoid_print`, неиспользуемый импорт `dart:async`, плюс
`dangling_library_doc_comments`, и файл не проходил `dart format`. Исправлено:
лишний импорт удалён, добавлен точечный `// ignore_for_file: avoid_print` с
обоснованием (это CLI-инструмент, вывод в stdout — его назначение),
doc-комментарий заменён на обычный, файл отформатирован. После правок:
`flutter analyze --no-pub lib test tool` — exit 0, `dart format
--set-exit-if-changed` — exit 0, сам скрипт — exit 0, «All 40 used symbols
present».

Замечание к DoD: пункт «регенерация на Windows и Unix даёт эквивалентный набор
public members» проверен только на Windows. Unix-прогон остаётся незакрытым —
это честно отражено и в «Остаточных рисках» отчёта.

### Независимое ревью root 2026-09-13

Статус остаётся `READY FOR REVIEW`: implementation defect не найден, но полный
DoD пока не выполнен.

- `tool/verify_bindings_audit.dart` повторно подтвердил 40/40 используемых
  symbols и отсутствие лишних public members; отдельно сравнены wrapper
  signatures до/после — из прежней поверхности исчез только неиспользуемый
  `nv21_to_rgb`.
- `flutter analyze --no-pub lib test` на Flutter 3.44.9 — exit 0.
- Общий focused review suite — 151/151 passed.
- Generated-файл содержит 40 используемых functions и `YUVDef`; native
  headers/sources не менялись.
- Блокер приёмки: отсутствует требуемая повторная генерация на Linux/macOS с
  машинным сравнением набора members и signatures. Windows-only evidence не
  позволяет поставить `DONE`.

### Повторное независимое ревью root 2026-09-14

Статус: `REJECTED`.

Предыдущее замечание не устранено: текущие GitHub Actions jobs не запускают
ffigen и не сравнивают generated ABI, поэтому зелёные run #24/#25 не являются
Unix evidence для YUV-26. Локально WSL optional component не установлен,
Docker/Podman отсутствуют; повторить Unix regeneration на этой машине нельзя.

Windows implementation и audit приняты: 40/40 используемых symbols найдены,
лишние CRT members отсутствуют, analyzer и focused VM suite 114/114 проходят.
Для повторного review требуется:

1. на Linux или macOS выполнить `flutter pub run ffigen --config ffigen.yaml`;
2. запустить `tool/verify_bindings_audit.dart`;
3. машинно сравнить с принятой Windows-генерацией имена, return/argument types
   всех public wrappers и приложить diff/логи;
4. подтвердить отсутствие неожиданного tracked diff после повторной генерации.

Native headers/sources менять не требуется. Generated bindings разрешено менять
только результатом ffigen, не вручную.

---

## YUV-28 — сократить дублирование Dart backend-классов после `0.2.5`

- Владелец: Opus
- Приоритет: P2 / architecture
- Статус: BLOCKED
- Зависимости: выполнять только после YUV-18; YUV-07 и YUV-20 должны быть DONE
- Anthropic-вариант: Claude Opus 5
- Scope:
  - shared Dart state/geometry/serialization abstractions
  - `lib/src/yuv/impl/io/yuv_image.dart`
  - `lib/src/yuv/impl/web/yuv_web.dart`
  - `lib/src/yuv/impl/yuv_stub.dart`
  - parity/characterization tests
- Post-release refactor; не блокирует YUV-18.

### Проблема

Три `YuvImageImpl` дублируют constructors, state, plane accessors, copy/bytes
logic и format dispatch. Shared `YuvGeometry` и `YuvCodec` уже сократили часть
расхождений, поэтому исходную оценку «около 700 строк» нужно пересчитать после
закрытия YUV-07/YUV-20, а не переносить старый план механически.

Пустое состояние accessor'ов формально расходится: IO бросает `RangeError`,
Web/stub возвращают zero-length sentinel. Для валидного публично созданного
изображения состояние практически недостижимо; shared sentinel нельзя
содержательно изменить, потому что его buffer имеет длину 0. Это contract debt,
а не подтверждённая corruption.

### Зафиксированное решение

1. Сначала снять актуальный duplication map после релиза и определить реально
   общий слой. Не создавать `YuvImageBase` только ради наследования.
2. Предпочесть composition для state/codec/geometry; backend-specific FFI/WASM
   dispatch оставить в `impl/*_io.dart` и `impl/*_web.dart`.
3. Зафиксировать единый контракт accessor'ов на недоступном/пустом состоянии и
   покрыть его characterization tests до изменения реализации.
4. Сохранить partial-WASM policy: общий state не означает feature parity.
5. Не менять native C, generated bindings и публичную mutation model.

### DoD

- Общая логика имеет одного владельца без циклических imports.
- IO/Web/stub сохраняют format, geometry, copy, serialization и revision
  contracts существующих tests.
- Удаление дублирования измерено diff/stat и не смешано с новым поведением.
- Empty-state contract одинаков и документирован либо доказано, что состояние
  недостижимо и sentinel удалён.
- Native и настоящий Chrome suites не получают новых падений.

### Проверка

```powershell
flutter analyze --no-pub lib test
flutter test
flutter test --platform chrome test/web
dart format --output=none --set-exit-if-changed lib test
git diff --check
git status --short
```

### Результат

Не заполнен.

---

## YUV-29 — удалить native-объявление `nv21_to_rgb` без реализации

- Владелец: Luna
- Приоритет: P3
- Статус: BLOCKED
- Зависимости: отдельное явное разрешение владельца на изменение `src/**/*.h`
- Anthropic-вариант: Claude Haiku 4.5; при обнаружении ABI consumer повысить до Claude Sonnet 5
- Scope:
  - `src/yuv/nv21.h`
  - `src/yuv/nv21/h/nv21_to_rgb.h`
  - regenerated bindings только если symbol ещё входит после YUV-26
- Опциональная native-header cleanup; не блокирует YUV-18.

### Проблема

Header объявляет и подключает `nv21_to_rgb`, но реализации и Dart-consumers
нет. Lazy lookup скрывает дефект до первого вызова. Это отдельная ABI hygiene
задача: она не должна блокировать ffigen filtering и не должна выполняться без
разрешения на native headers.

### Зафиксированное решение

1. Перед изменением повторно проверить native exports и все consumers.
2. При подтверждённом отсутствии consumer удалить declaration header и include
   из `nv21.h`; новую C-реализацию без отдельного требования не писать.
3. Если generated binding ещё содержит symbol, регенерировать его штатно после
   header change; generated-файл вручную не редактировать.
4. Не менять существующий NV21/UV compatibility contract.

### DoD

- В headers и generated bindings нет declaration без реализации.
- Все реально используемые Dart symbols по-прежнему резолвятся.
- Приложено явное разрешение владельца на изменение headers.
- Native build/runtime smoke и анализатор проходят.

### Проверка

```powershell
flutter pub run ffigen --config ffigen.yaml
flutter analyze
flutter test
<native build/runtime smoke>
git diff --check
git status --short
```

### Результат

Не заполнен.

---

## YUV-30 — зафиксировать native effects/blur/ROI contract

- Владелец: Root (Architect/Reviewer)
- Anthropic-вариант: Claude Opus 5
- Ожидаемое reasoning: High
- Приоритет: P0 / architecture gate
- Статус: DISCOVERED
- Зависимости: решение владельца по пяти публичным контрактам
- Scope:
  - публичные docs для `grayscale`, `blackwhite`, `negate`, `gaussianBlur`,
    `boxBlur`, `meanBlur`;
  - semantics `rect`, `radius`, `sigma`, border, alpha и padding;
  - решение о failure ABI для patch `0.2.5` и будущего minor release;
  - обновление Architect Decision/зависимостей YUV-22, YUV-23, YUV-31…YUV-36.
- Non-goal: реализация Dart/C, изменение manifest или thresholds.

### Проблема

Проверенный C-аудит подтвердил конфликтующие фактические контракты. Blur
размывает разные planes/channels в BGRA, I420 и legacy-`nv21`; mean использует
`radius / 2`, остальные реализации — `2 * radius + 1`; rect ограничивает только
часть planes; YUV negate является raw-plane transform, а reference oracle ждёт
RGB-visible результат. Публичная документация этих различий не определяет.

Без решения владельца исполнитель вынужден сам выбирать публичное поведение,
что запрещено orchestration protocol и делает YUV-22/YUV-23 неготовыми.

### Требуется решение владельца

1. Effects: RGB-visible parity между форматами либо format-specific plane-native
   semantics. Рекомендация архитектора: RGB-visible parity для grayscale,
   blackwhite и negate, согласованная с independent oracle YUV-10.
2. Blur: RGB-visible parity либо deterministic plane-native convolution.
   Рекомендация архитектора: plane-native blur одинаковым kernel/radius/border
   по всем logical color planes, BGRA alpha не менять. Для subsampled chroma
   строгая visible boundary невозможна без format conversion: один chroma
   sample разделяют до четырёх luma pixels.
3. `rect`: crop-style `floor(left/top)`, `ceil(right/bottom)`, clamp к кадру и
   no-op для пустого результата либо `ArgumentError`. Рекомендация: clamp/no-op.
   Для 4:2:0 отдельно выбрать: менять все chroma samples, чьи 2×2 footprints
   пересекают ROI, либо не менять boundary chroma. Рекомендация: intersecting
   blocks с явным предупреждением, что RGB pixels у границы делят chroma.
4. Параметры: `radius == 0` как no-op, отрицательный radius и non-positive
   `sigma` как `ArgumentError`; требуется выбрать документируемую верхнюю
   границу radius. Рекомендация safety-cap: `radius <= 256`.
5. Allocation failure в `0.2.5`: сохранить void ABI и гарантировать atomic
   no-op либо вводить новые status-returning symbols сейчас. Рекомендация:
   сохранить ABI в patch, новые status symbols вынести в YUV-36/`0.3.0`.

### Architect Decision

До ответа владельца не зафиксирован. Исполнителям запрещено начинать зависящие
задачи или выбирать один из вариантов самостоятельно.

### DoD

- [ ] Зафиксированы ответы по всем пяти пунктам без неоднозначных слов.
- [ ] Определены exact formula/rounding/threshold и видимые результаты effects.
- [ ] Определены planes/channels, radius, border и ROI mapping каждого blur.
- [ ] Определено поведение invalid/empty/outside/fractional rect и параметров.
- [ ] Решено, что остаётся в `0.2.5`, а что требует нового ABI/minor release.
- [ ] YUV-22, YUV-23, YUV-31…YUV-36 синхронизированы с решением.
- [ ] Runtime-код и native sources в этой задаче не изменены.

### Результат

Не заполнен.

---

## YUV-31 — исправить stride/odd safety в rotate, crop и flip

- Владелец: Opus
- Anthropic-вариант: Claude Opus 5
- Ожидаемое reasoning: Medium
- Приоритет: P0
- Статус: BLOCKED
- Зависимости: YUV-30, YUV-33 и отдельное разрешение владельца на изменение native C
- Scope:
  - `src/yuv/{bgra8888,yuv420,nv21}/*{rotate,crop,flip}.c`;
  - IO wrappers только для безопасной нормализации/ошибок;
  - focused native/Web transform tests, canary и sanitizer cases;
  - regenerated WASM из того же commit.

### Проблема

Выводы C-аудита подтверждены исходниками:

- I420/NV rotate использует `dstWidth` вместо `dst->yRowStride`, source pixel
  stride вместо destination stride и floor `dst->width / 2` для chroma;
- BGRA rotate игнорирует оба rowStride и копирует `src->yPixelStride` bytes в
  destination, что допускает OOB при custom stride;
- crop вычисляет destination rows как tight и копирует `logicalWidth *
  pixelStride`, то есть принимает gap/padding за sample bytes; chroma crop
  использует floor и теряет trailing samples на odd geometry;
- horizontal flip переставляет `pixelStride` bytes вместо sample size
  `1/2/4`, BGRA игнорирует rowStride;
- flip имеет multi-allocation leaks и vertical path может завершиться после
  частичной mutation при OOM.

Неподдерживаемый raw `rotationDegrees` недостижим через публичный Dart enum, но
остаётся defensive-boundary дефектом экспортируемых C symbols. Stride/crop/flip
дефекты через публичные custom planes достижимы.

Probe I420 rotate 180° с `yPixelStride=2,rowStride=3` подтвердил collision
destination indices; crop `3x3` записал лишь один из четырёх chroma samples.

### Architect Decision

1. Адресовать source и destination только их собственными row/pixel strides.
2. Размер logical sample фиксирован форматом: 1 byte Y/planar U/V, 2 bytes
   interleaved UV, 4 bytes BGRA; padding никогда не копировать как pixel data.
3. Использовать ceil chroma geometry из YUV-33. Mapping odd crop origin следует
   точному ROI/chroma policy, принятому YUV-30.
4. `rotate` принимает только enum-derived 0/90/180/270; C boundary defensive
   отклоняет иные degrees и несовместимую destination geometry без записи.
5. Horizontal flip использует scalar/fixed sample swap без heap allocation.
   Vertical flip выделяет scratch один раз до первой записи; OOM — atomic no-op.
6. Не менять установленный legacy `nv21` `(U,V)` byte order.

### DoD

- [ ] Tight и минимально padded layouts проходят rotate/crop/flip для трёх форматов.
- [ ] Проверены `1x1`, `1xN`, `Nx1`, odd/even и все rotation values.
- [ ] Source/destination padding и canaries не читаются/не меняются как samples.
- [ ] Odd chroma не теряет trailing row/column; crop phase соответствует YUV-30.
- [ ] Allocation failure до vertical flip оставляет bytes неизменными; текущий
      false-positive revision bump явно зафиксирован как ограничение void ABI
      до YUV-36.
- [ ] ASan/UBSan harness YUV-34 не сообщает OOB/UB/leaks.
- [ ] Native и real WASM cases используют одинаковые fixtures.
- [ ] Native C изменяется только после отдельного разрешения.

### Результат

Не заполнен.

---

## YUV-32 — унифицировать RGBA/BGRA → YUV conversion contract

- Владелец: Opus
- Anthropic-вариант: Claude Opus 5
- Ожидаемое reasoning: Medium
- Приоритет: P1
- Статус: BLOCKED
- Зависимости: YUV-30, YUV-33 и отдельное разрешение владельца на изменение native C
- Scope:
  - `src/yuv/bgra8888/bgra8888_{from_rgba,to_i420,to_nv21}.c`;
  - shared color conversion helpers;
  - corresponding native/Web reference tests and regenerated WASM;
  - public conversion docs when coefficients/range become contractual.

### Проблема

`yuv420_from_rgba8888` и `nv21_from_rgba8888` используют BT.601 limited range и
average реального 2×2 блока. BGRA→I420/NV применяет другую full-range matrix и
берёт chroma только из top-left pixel. Один и тот же RGBA/BGRA кадр поэтому даёт
разные YUV bytes; probe получил Y `[82,41,41,41]` против `[76,28,28,28]` и UV
`[202,142]` против `[85,255]`.

Отдельно `bgra8888_from_rgba8888` пишет tight index `(y*width+x)*4` и игнорирует
destination descriptor. Dart сейчас смягчает это staging-копией, но exported C
symbol остаётся tight-only без объявленного precondition.

### Architect Decision

1. Канальный порядок input не меняет color matrix/range/rounding: canonical
   contract — BT.601 limited/video range, уже используемый RGBA→YUV paths.
2. U/V считать average всех реально существующих pixels в 2×2 block; odd edge
   делить на actual sample count.
3. Legacy `nv21` хранит установленный `(U,V)` order.
4. Использовать common fixed-point helpers и shared checked geometry YUV-33.
5. `bgra8888_from_rgba8888` обязан использовать destination row/pixel strides;
   input RGBA остаётся tight согласно публичному Dart contract.
6. Manifest не подгонять под current DLL; любое осознанное изменение oracle —
   отдельный reviewed reference update.

### DoD

- [ ] RGBA и эквивалентный BGRA input дают одинаковые Y/U/V logical samples.
- [ ] Tight/padded и odd/even cases сохраняют descriptor geometry и canaries.
- [ ] 2×2 chroma reducer и odd edges сверены с independent oracle.
- [ ] Native и WASM проходят одинаковые conversion case IDs/thresholds.
- [ ] Документация явно называет matrix/range/rounding и legacy UV order.
- [ ] Generated bindings не редактировались вручную.
- [ ] Native C изменяется только после отдельного разрешения.

### Результат

Не заполнен.

---

## YUV-33 — ввести checked native descriptor/index/allocation primitives

- Владелец: Opus
- Anthropic-вариант: Claude Opus 5
- Ожидаемое reasoning: Medium
- Приоритет: P0 / foundation
- Статус: BLOCKED
- Зависимости: YUV-30 и отдельное разрешение владельца на изменение native C
- Scope:
  - `src/yuv/yuv.h`, `src/yuv/utils/h/yuv_utils.h` и новый узкий shared helper при необходимости;
  - C-only unit harness для descriptor, ceil chroma и checked arithmetic;
  - adoption contract для YUV-22, YUV-23, YUV-31 и YUV-32.
- Non-goal: массовая миграция всех operations в одном foundation commit.

### Проблема

`yuv_index` и allocation expressions вычисляются в signed `int`; `width *
height * 4`, `2 * radius + 1` и `y * rowStride + x * pixelStride` могут
переполниться до conversion в `size_t`. C functions не имеют общей проверки
positive geometry/strides, required pointers, format-specific sample sizes или
совместимости source/destination descriptors.

`YUVDef` не содержит фактических buffer lengths. Поэтому C boundary может
доказать только минимально необходимый span и арифметическую корректность, но не
может проверить, сколько памяти caller действительно выделил. Это ограничение
нельзя скрывать обещанием полной buffer validation.

### Architect Decision

1. Заменить macro-indexing на checked `size_t` helpers для multiplication,
   addition, plane span и sample offset; overflow возвращает failure до доступа
   к памяти.
2. Добавить format/operation-specific descriptor validation: positive geometry,
   non-null required planes, positive strides, `rowStride >= minimum span`,
   supported pixel stride/sample size и compatible destination dimensions.
3. Один shared ceil helper `(value / 2) + (value % 2)` без overflow формулы
   `(value + 1) / 2`.
4. Helpers не читают pointers и тестируются на boundary values без выделения
   многогигабайтных frames.
5. Существующие exported void symbols в `0.2.5` не менять без решения YUV-30;
   status-returning ABI вынесен в YUV-36.
6. Каждый operation consumer обязан завершаться до первой mutation при failed
   validation/allocation и иметь единый cleanup path.

### DoD

- [ ] Checked add/multiply/index/span helpers покрыты overflow-boundary tests.
- [ ] Descriptor validator покрывает null pointers, zero/negative dimensions,
      undersized stride, unsupported pixel stride и incompatible destination.
- [ ] Tests не требуют реальной огромной allocation.
- [ ] Ни один helper не обещает проверить неизвестную фактическую buffer length.
- [ ] Adoption points перечислены по task/file; массовый unrelated rewrite отсутствует.
- [ ] Clang strict warnings и sanitizer unit harness проходят.
- [ ] Native C изменяется только после отдельного разрешения.

### Результат

Не заполнен.

---

## YUV-34 — добавить native ASan/UBSan safety gate

- Владелец: Terra
- Anthropic-вариант: Claude Sonnet 5
- Ожидаемое reasoning: Medium
- Приоритет: P1 / release gate
- Статус: BLOCKED
- Зависимости: YUV-22, YUV-23, YUV-31, YUV-32, YUV-33
- Scope:
  - C test harness outside `build/`;
  - GitHub Actions Ubuntu job with Clang ASan/UBSan/LSan where supported;
  - canary, invalid-parameter and allocation-failure cases;
  - documented compiler/version/commands and source commit.

### Проблема

Flutter reference tests обнаруживают неправильные pixels, но не доказывают
отсутствие OOB, use of uninitialized memory, integer UB или leaks внутри C.
Аудит опирался на one-off Clang/probe runs; постоянного required gate нет.

### Architect Decision

1. Добавить отдельный native C harness, который напрямую вызывает exported
   operations на tight/padded/odd descriptors с prefix/suffix/row canaries.
2. Required Ubuntu CI job собирает текущие `src/yuv` с `clang` и
   `-fsanitize=address,undefined`; leak detection включается там, где стабильно
   поддерживается runner.
3. Cases включают invalid rect/radius/sigma/geometry, overflow arithmetic,
   allocation-failure injection и atomic no-op.
4. Job не использует checked-in binaries, не читает `build/`, не имеет
   `continue-on-error` и печатает число исполненных cases.
5. Web parity остаётся в integration harness; sanitizer job её не заменяет.

### DoD

- [ ] Harness детерминирован и хранится вне исключённых каталогов.
- [ ] ASan/UBSan job required и падает на sanitizer report/non-zero exit.
- [ ] Покрыты все regression probes C-01…C-09 и H-01/H-02, релевантные памяти.
- [ ] Allocation injection доказывает cleanup и отсутствие partial commit.
- [ ] В tracker записаны run URL, toolchain versions, case count и provenance.
- [ ] Existing Flutter analyzer/tests не регрессировали.

### Результат

Не заполнен.

---

## YUV-35 — синхронизировать C API ownership, mutation и комментарии

- Владелец: Terra
- Anthropic-вариант: Claude Sonnet 5
- Ожидаемое reasoning: Low
- Приоритет: P2 / optional cleanup
- Статус: BLOCKED
- Зависимости: YUV-29 и отдельное разрешение владельца на изменение native headers
- Не блокирует YUV-18.
- Scope:
  - C headers и matching definitions;
  - `src/yuv/yuv.c`, NV comments и `src/yuv/utils/h/log.h`;
  - ffigen regeneration only if declarations change.

### Проблема

- NV comments говорят VU, хотя установленный compatibility contract — `(U,V)`.
- In-place functions принимают `const YUVDef *src`, хотя меняют pointee planes;
  const относится к struct, но создаёт ложное впечатление immutable operation.
- Non-Android logging объявляет `debug/warn/error`, Android — `LOGD/LOGW/LOGE`.
- `freeYUVDef` определена, но не объявлена/не экспортируется и не имеет consumer;
  Dart уже владеет struct/planes и освобождает их через `YUVDefClass.dispose()`.
- Missing `nv21_to_rgb` declaration/definition mismatch остаётся отдельной YUV-29.

### Architect Decision

1. Исправить только документационную/сигнатурную правду без изменения runtime
   semantics: legacy `nv21` comments называют interleaved `(U,V)`.
2. In-place definitions/headers принимают `YUVDef *image`; read-only source и
   writable destination различаются именами и const-correctness.
3. Унифицировать macros как `LOGI/LOGD/LOGW/LOGE` на всех платформах.
4. Если повторный consumer search пуст, удалить `freeYUVDef` как dead code;
   не экспортировать второй ownership path рядом с Dart allocator.
5. Не объединять с YUV-29 и не редактировать generated bindings вручную.

### DoD

- [ ] Headers и definitions совпадают; strict C compile не даёт const mismatch.
- [ ] NV comments нигде не заявляют VU для текущего `(U,V)` contract.
- [ ] Logging macro surface одинакова на Android/non-Android.
- [ ] `freeYUVDef` либо удалена после доказанного отсутствия consumers, либо
      задача возвращена архитектору с найденным ownership requirement.
- [ ] ABI symbols/runtime output не изменились.
- [ ] Native C/header изменения выполнены только после разрешения.

### Результат

Не заполнен.

---

## YUV-36 — спроектировать status-returning native ABI

- Владелец: Opus
- Anthropic-вариант: Claude Opus 5
- Ожидаемое reasoning: Medium
- Приоритет: P2 / post-release
- Статус: BLOCKED
- Зависимости: после `0.2.5`, YUV-33 и решение YUV-30
- Не блокирует YUV-18.

### Проблема

Все 40 exported operations возвращают `void`. При invalid descriptor или OOM
Dart не может отличить success от atomic no-op и увеличивает revision как после
успеха. Изменение return type существующего symbol небезопасно для patch ABI.

### Architect Decision

1. Для `0.2.5` сохранить существующие symbols/signatures и требовать safe
   atomic no-op на C failure.
2. Для следующего minor спроектировать additive `*_v2`/единый status contract,
   не менять значение существующего symbol на месте.
3. Status enum различает success, invalid argument, unsupported layout,
   overflow и allocation failure; Dart переводит его в документированные
   exceptions и не меняет revision при failure.
4. Ownership buffer lengths/descriptor versioning рассмотреть явно, поскольку
   текущий `YUVDef` не несёт allocation lengths.

### DoD

- [ ] Есть reviewed ABI proposal с compatibility/migration table.
- [ ] Старые symbols продолжают работать на поддерживаемом happy path.
- [ ] v2 status и Dart exception mapping покрыты tests.
- [ ] Failed operation не меняет bytes/metadata/revision.
- [ ] Headers/ffigen обновляются штатно только в реализации отдельного minor.

### Результат

Не заполнен.

---

## YUV-37 — оптимизировать blur scratch и алгоритмическую сложность

- Владелец: Terra
- Anthropic-вариант: Claude Sonnet 5
- Ожидаемое reasoning: Medium
- Приоритет: OPT / post-release
- Статус: BLOCKED
- Зависимости: после YUV-23
- Не блокирует YUV-18.

### Проблема

Gaussian helper делает O(width+height) heap allocations на plane и строит один
kernel до трёх раз за публичный вызов. NV box chroma и mean paths используют
O(W*H*r²), хотя Y path уже содержит separable sliding-window подход. Vertical
flip allocation устранит YUV-31 как safety fix и сюда не входит.

### Architect Decision

После фиксации reference output переиспользовать один kernel и bounded scratch,
перевести 1/2/4-byte samples на общий stride-aware separable primitive. Любая
оптимизация обязана сохранить exact/tolerance output YUV-23 и border/ROI policy.

### DoD

- [ ] Allocation count не зависит от width+height.
- [ ] Box/mean complexity не хуже O(W*H) для fixed channel count.
- [ ] Benchmark фиксирует before/after time и peak allocations.
- [ ] Native/Web reference output и sanitizer suite остаются зелёными.
- [ ] Оптимизация не смешана с correctness commit YUV-23.

### Результат

Не заполнен.

---

## YUV-38 — оптимизировать block conversion после YUV-32

- Владелец: Terra
- Anthropic-вариант: Claude Sonnet 5
- Ожидаемое reasoning: Low
- Приоритет: OPT / post-release
- Статус: BLOCKED
- Зависимости: после YUV-32
- Не блокирует YUV-18.

### Проблема

BGRA→I420/NV сейчас вычисляет U/V для каждого pixel, хотя пишет chroma один раз
на 2×2 block. После YUV-32 четыре Y и одна averaged UV pair могут считаться
block-wise общим helper без выбрасывания 75% chroma arithmetic.

### Architect Decision

Оптимизировать только после принятого YUV-32 oracle. Обрабатывать 2×2 blocks с
actual sample count на odd edges; сохранить BT.601 limited coefficients,
rounding, strides и legacy `(U,V)` order byte-for-byte.

### DoD

- [ ] Native/Web output совпадает с принятым YUV-32 reference.
- [ ] Odd/padded cases и canaries остаются зелёными.
- [ ] Benchmark показывает эффект без изменения публичного API.
- [ ] Optimization commit не меняет manifest/thresholds.

### Результат

Не заполнен.

---

## YUV-18 — финальная приёмка и подготовка `0.2.5`

- Владелец: Terra
- Приоритет: P0 / release gate
- Статус: BLOCKED
- Зависимости: YUV-06, YUV-08, YUV-09, YUV-12, YUV-13,
  YUV-21, YUV-22, YUV-23, YUV-30, YUV-31, YUV-32, YUV-33, YUV-34
  (YUV-02/YUV-07/YUV-14/YUV-15/YUV-17/YUV-20 приняты)
- Scope:
  - интеграционное ревью всех task commits;
  - `pubspec.yaml` и верхняя запись `CHANGELOG.md`;
  - release verification без tag/push;
  - никаких новых feature/refactor изменений.

### Проблема

`0.2.4` уже помечен tag, но имеет Web compile blocker, ложный Web CI, native memory-safety риски, потерю Y в `swapNv()` и неподтверждённые Linux/macOS paths. Отдельные зелёные проверки не доказывают готовность package целиком.

### Зафиксированное решение

1. Независимо пересмотреть каждый task diff и заполненный результат; не принимать самооценку модели без повторного запуска ключевых gates.
2. Проверить, что зависимости выполнены и ни одна C-задача не обошла approval.
3. Убедиться, что `failed-test-cases.md` не содержит unresolved P0/P1 failures и что все resolved entries имеют повторный успешный reference run.
4. Провести clean-checkout matrix:
   - Dart/Flutter analysis;
   - VM/widget tests;
   - настоящий Chrome Web suite;
   - native build/runtime smoke на Windows, Linux, macOS;
   - Android/iOS build checks;
   - publish dry run.
5. Установить `0.2.5` одновременно в `pubspec.yaml` и верхней записи `CHANGELOG.md`.
6. Проверить содержимое publish archive на отсутствие `_tmp_*`, локальных DLL и иных developer artifacts, не читая `build/`.
7. Не создавать tag и не делать push без отдельного запроса владельца.

### DoD

- Все перечисленные обязательные зависимости имеют статус `DONE` и независимое
  verification evidence. Опциональные YUV-24, YUV-26, YUV-29 и
  post-release YUV-28 выпуск не блокируют.
- Полная reference matrix на `test_pattern_512.png` проходит на native и Web либо имеет явно согласованные ограничения; unresolved P0/P1 failures отсутствуют.
- P0/P1 findings из аудита либо устранены, либо явно сняты владельцем с документированным основанием.
- `flutter analyze` проходит из корня.
- Полный VM suite и реальный Chrome suite проходят.
- Native runtime smoke подтверждён на Windows/Linux/macOS; mobile builds подтверждены.
- `flutter pub publish --dry-run` завершается с 0 warnings.
- `pubspec.yaml` и верхняя версия CHANGELOG равны `0.2.5`.
- Рабочее дерево содержит только ожидаемые release changes.
- Tag/push не выполнялись.

### Проверка

```powershell
flutter analyze
flutter test
flutter test --platform chrome test/web
flutter pub publish --dry-run
git diff --check
git status --short --branch
git diff --stat 0.2.4..HEAD
```

К результату приложить platform-specific build/runtime команды, CI URLs и финальный список файлов publish dry run.

### Результат

Не заполнен.
