# yuv_ffi: текущая очередь работ

Здесь находятся только задачи, которые инженер утвердил и которые можно взять
сейчас: `TODO`, `IN PROGRESS` и `READY FOR REVIEW`. Заблокированные,
отложенные, discovery и optional/post-release карточки вместе с полным описанием
находятся в [todo-waitlist.md](todo-waitlist.md).

## Общий чеклист

| Готово | ID | Владелец | Anthropic-вариант | Приоритет | Статус | Зависит от | Краткое описание |
|---|---|---|---|---|---|---|---|
| [ ] | YUV-06 | Terra | Claude Opus 5 | P1 | TODO | — | Восстановить загрузку и упаковку native-библиотеки на Linux/macOS |
| [ ] | YUV-08 | Luna | Claude Sonnet 5 | P2 | TODO | — | Восстановить Web parity для padded BGRA и публичного tight-buffer контракта |
| [ ] | YUV-12 | Luna | Claude Sonnet 5 | P1 | TODO | — | Прогнать ту же матрицу по эталону на реальном Web/WASM backend |

## Правила очереди

- Архитектор добавляет карточку в `todo.md` только если она готова к работе и
  заранее одобрена инженером. Во всех остальных случаях карточка с полным
  описанием создаётся в `todo-waitlist.md`.
- После независимого ревью ревьюер либо возвращает задачу в `TODO` с конкретными
  замечаниями, либо удаляет принятую задачу из `todo.md`. Отдельный архив
  завершённых задач не ведётся: доказательства остаются в task commit, tests и
  истории Git.
- При принятии задачи ревьюер в том же tracker update удаляет все связанные
  записи из `failed-test-cases.md` (строку сводки и полную секцию, если она
  есть). Принятая задача не оставляет `RESOLVED`-архив в журнале падений.
- Ревьюер проверяет зависимости и может перенести готовую карточку из waitlist
  в `todo.md`; при переносе синхронно перемещаются строка чеклиста и полная
  секция задачи.
- `TODO` — задача одобрена и доступна; `IN PROGRESS` — один исполнитель начал
  работу; `READY FOR REVIEW` — реализация и evidence готовы к независимой
  проверке. Исполнитель не ставит `DONE`.
- Любое изменение native C/header требует заранее записанного контракта и
  regression/characterization test cases: они обязаны воспроизводить прежнее
  неверное поведение либо проверять затронутый native path и подтверждать
  правильный результат после исправления. Одного build/analyzer недостаточно.
- Установленный legacy public `nv21` с фактическим `(U,V)` порядком сохраняется.
  Web остаётся частичным WASM backend.
- Не читать и не включать в scope `build/`; generated FFI bindings редактировать
  только через header/config и ffigen.

## Общий Definition of Done

- Scope карточки соблюдён, несвязанные рабочие изменения сохранены.
- Для изменённого поведения есть test case с expected result; для native C —
  обязательный regression/characterization case и native runtime/smoke evidence.
- Выполнены команды из секции «Проверка», приложены exit code и фактический
  счётчик тестов; Web подтверждён с `kIsWeb == true`.
- `flutter analyze`, formatter для изменённых Dart-файлов, `git diff --check` и
  `git status --short` приложены к результату.
- Native C меняется только в отдельном task commit; если меняется ABI, bindings
  регенерируются штатно, вручную generated файл не редактируется.

---

## YUV-06 — восстановить Linux/macOS packaging и runtime loading

- Владелец: Terra
- Приоритет: P1
- Статус: TODO
- Зависимости: нет; разрешение владельца на native C получено 2026-09-14.
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
- Добавлен regression/smoke case, подтверждающий загрузку и реальную BGRA/YUV-операцию на каждом изменённом native path; он должен быть воспроизводимо красным до исправления packaging/layout.

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

---

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

---

---
