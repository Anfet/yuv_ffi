# yuv_ffi: текущая очередь работ

Здесь находятся только задачи, которые инженер утвердил и которые можно взять
сейчас: `TODO`, `IN PROGRESS`, `READY FOR REVIEW` и `REJECTED`, если исправления
по ревью должны быть выполнены в текущем batch. Заблокированные,
отложенные, discovery и optional/post-release карточки вместе с полным описанием
находятся в [todo-waitlist.md](todo-waitlist.md).

## Общий чеклист

| Готово | ID | Владелец | Anthropic-вариант | Приоритет | Статус | Зависит от | Краткое описание |
|---|---|---|---|---|---|---|---|
| [ ] | YUV-08 | Luna | Claude Sonnet 5 | P2 | REJECTED | isolated commit; required CI target; comment fix | Восстановить Web parity для padded BGRA и публичного tight-buffer контракта |

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
  проверке; `REJECTED` — ревьюер вернул задачу с конкретными исправлениями в
  рамках текущего batch. Исполнитель не ставит `DONE`.
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

## YUV-08 — вернуть tight BGRA contract на Web

- Владелец: Luna
- Приоритет: P2
- Статус: REJECTED
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

Web `toBgra8888()` для `bgra8888` больше не возвращает плоскость целиком: при
`rowStride != width * 4` строится tight-копия построчно, как в native
(`lib/src/yuv/impl/io/yuv_image.dart`). Условие сравнивает только `rowStride`,
как native; `YuvGeometry.isTightBgra` намеренно не используется — он
дополнительно требует `pixelStride == 4`, из-за чего tight-плоскость с
нестандартным pixelStride ушла бы в repack-ветку, которая копирует строки
целиком и pixelStride всё равно не учитывает.

Изменены:

- `lib/src/yuv/impl/web/yuv_web.dart`
- `example/integration_test/wasm_parity_edge_cases_test.dart` (новый)

Evidence — реальный Chrome, `kIsWeb == true`:

```text
cd example
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/wasm_parity_edge_cases_test.dart -d chrome
00:00 +0: (setUpAll)
00:00 +1: toBgra8888 repacks a padded BGRA plane into exactly width*height*4 tight bytes
00:00 +2: toBgra8888 on a tight BGRA plane (rowStride == width*4) returns the tight bytes unchanged
00:00 +3: (tearDownAll)
00:00 +4: All tests passed!
```

Негативный контроль: фикс убран (`git stash`), прогон повторён на багованном
коде — падает именно padded-кейс, tight-кейс продолжает проходить, то есть тест
различает фикс и его откат, а не проходит безусловно:

```text
00:00 +1: toBgra8888 repacks a padded BGRA plane ... [E]
  Expected: <60>
    Actual: <108>
  toBgra8888 must always return exactly width*height*4 bytes
  wasm_parity_edge_cases_test.dart 48:5
00:00 +3 -1: Some tests failed.
```

`60 = 5*3*4` (tight), `108 = 3*(5*4+16)` (padded) — в результат протекал padding.

`flutter analyze lib` — No issues found. `dart format --set-exit-if-changed`
для `lib` и обоих web-тестов — 0 changed.

Границы утверждения: доказан контракт длины и точного порядка байт для
padded/tight BGRA на Web. Остальные BGRA-операции по-прежнему отклоняют padded
плоскость через `_requireTightBgraFor` (YUV-23), это здесь не менялось.

### Независимое ревью root 2026-09-14

Статус: `REJECTED`, количество отклонений: 1. Поведение исправления подтверждено
независимым Chrome-прогоном на Flutter 3.38.10: 4/4 tests passed, включая
padded exact bytes, tight bytes и copy independence. `flutter analyze --no-pub
lib example/integration_test/wasm_parity_edge_cases_test.dart` также прошёл.

До повторного review требуется:

1. оформить YUV-08 отдельным commit; сейчас production-файл и regression test
   лежат в рабочем дереве вместе с незавершённой YUV-12;
2. добавить `integration_test/wasm_parity_edge_cases_test.dart` в массив
   `targets` required `wasm-web-integration`, чтобы regression выполнялся после
   принятия, а не только в локальном разовом прогоне;
3. исправить комментарий в `toBgra8888()`: при `rowStride == width * 4` и
   `pixelStride != 4` `YuvGeometry.isTightBgra` выбрал бы repack, тогда как
   текущий код и native выбирают return-copy. Сейчас комментарий утверждает
   обратное. Поведение и установленный parity contract менять не требуется.

---
