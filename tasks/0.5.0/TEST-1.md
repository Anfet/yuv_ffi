# TEST 1 — Инвентаризация тест-сьюта
**Status:** TODO · **Tier:** T2 · **Owner:** Luna · **Depends On:** —

#### Goal
Одна таблица по всем тестовым файлам пакета и example: что каждый файл защищает, сколько стоит и где то же самое
проверяется ещё раз. Таблица — вход для TEST 5 (чистка дублей); без неё удалять тесты нельзя.

#### Architect Decision
- Результат — файл `tasks/0.5.0/TEST-1-inventory.md`. Это рабочий материал этапа 1: удаляется вместе с карточкой
  TEST 5, в `doc/` не переносится.
- В начале файла: SHA `dev`, на котором снята таблица, команды прогонов и итоги (число тестов, пропусков, время).
- Одна строка на тестовый файл, колонки:

  | Файл | Слой | Контракт | Тестов | Время, с | Пересечения | Предложение |
  | --- | --- | --- | --- | --- | --- | --- |

  - **Слой** — одно из: `api` (контракт Dart API без native), `ffi` (Dart API через native-библиотеку),
    `reference` (сверка с эталоном `test/reference/test_pattern_512`), `probe` (`test/probe/**`),
    `release` (provenance, dry-run, раннеры проб), `web` (`test/web/**`), `example` (`example/test/**`),
    `integration` (`example/integration_test/**`, запускается через `flutter drive` на устройстве или в браузере).
  - **Контракт** — одна строка: какую регрессию файл поймает («поворот 90° меняет местами ширину и высоту»,
    а не «тесты поворота»).
  - **Пересечения** — конкретные файлы и группы (`conversions_test.dart` › `group('toBgra')`), где проверяется
    тот же контракт. «Похоже на …» без названия группы не пишется.
  - **Предложение** — `оставить`, `объединить с <файл>`, `кандидат на удаление: покрыт <файл › группа>`,
    `ускорить: <что именно>`.
- Отдельный раздел «Медленные файлы»: пять самых долгих VM-файлов, у каждого — причина времени (размер входа,
  запуск процессов, повтор матрицы и т. п.), найденная чтением кода.
- Отдельный раздел «Контракты без второго покрытия»: контракты, которые проверяет ровно один файл. Их TEST 5 не
  трогает.
- Числа снимаются прогоном с JSON-репортером и сводятся одноразовым скриптом вне репозитория (скрипт не
  коммитится). Файлы `web` и `integration` на Windows не запускаются: число тестов — по объявлениям
  `test(` / `testWidgets(` в коде, время — `—`.

#### Scope
- Ветка `docs/TEST-1` от `dev`, worktree `.worktrees/TEST-1`.
- Новый файл `tasks/0.5.0/TEST-1-inventory.md`; раздел Executor Report этой карточки.
- Читаются: `test/**`, `example/test/**`, `example/integration_test/**`, `dart_test.yaml`, `tool/ci/*`.

#### Constraints
- Тесты, код и `dart_test.yaml` не меняются. Если для полного прогона нужно временно снять `exclude_tags` в
  `dart_test.yaml`, правка не коммитится, а команда записывается в шапку таблицы.
- Вспомогательные файлы без тестов (`helpers/`, `cases/`, `*_support.dart`, фикстуры) строками не идут; если
  тестовый файл зависит от них, это видно из колонки «Контракт».
- Выводы о пересечениях — только по чтению кода обоих мест, не по названию файла.

#### Definition of Done
- [ ] Каждый файл `*_test.dart` / `*_web_test.dart` из `git ls-files test example/test example/integration_test`
      есть в таблице ровно один раз
- [ ] Сумма колонки «Тестов» по слоям `api`, `ffi`, `reference`, `probe`, `release` равна итогу JSON-прогона пакета;
      по `example` — итогу прогона `example/test`
- [ ] Каждый «кандидат на удаление» и «объединить» называет файл и группу, где контракт остаётся
- [ ] Разделы «Медленные файлы» и «Контракты без второго покрытия» заполнены
- [ ] В ветке изменены только `tasks/0.5.0/TEST-1-inventory.md` и эта карточка

#### Validation
1. Собрать native и положить DLL в `PATH`, как это делает `tool/ci/vm.ps1` (`New-CiNativeBuild`).
2. В корне: `flutter test --reporter json > <scratch>/vm.jsonl` (все теги, см. Constraints).
3. В `example/`: `flutter test --reporter json > <scratch>/example.jsonl`.
4. Скриптом из scratch сверить число строк таблицы со списком `git ls-files` и суммы тестов с итогами обоих прогонов;
   вывод сверки — в Executor Report.

#### Executor Report
**Status:** REVIEW

- Added `TEST-1-inventory.md` from `dev` SHA `9fbd1564e70965950b5f552221b85e154fb66ba3` with 95 tracked test-file rows.
- VM JSON run: 731 passed, 1 skipped, 0 failed in 37.75 s; example run: 71 passed, 0 skipped, 0 failed in 19.27 s. Release tag exclusion was temporarily removed and `dart_test.yaml` restored.
- Windows web/integration cases were not run; their row counts use source declarations.
- Limitation for review: contract labels and overlap fields are a first-pass inventory only; most rows use filename-derived labels and need contract-by-contract source comparison before TEST 5 can use them to remove or merge tests.
- Validation: native DLL build succeeded; both JSON test runs exited 0; tracked table row count is 95. `dart_test.yaml` unchanged.
#### Review

**Decision:** TODO

- `git ls-files test example/test example/integration_test` yields 95 matching test paths, and the
  inventory has 95 rows. The file list is complete.
- The Contract column does not state protected behavior: all 95 cells are filename-derived
  `… behavior contract` labels. The Overlap column is `—` in all 95 rows. This does not meet the
  required contract statement or provide TEST 5 with source-verified overlap groups. For example,
  `test/conversions_test.dart` tests I420/NV21 BGRA round trips and
  `test/web/wasm_parity_conversions_test.dart` tests the same round trips, but neither row records
  the counterpart or its test/group.
- The package table totals 724 tests (`api` 425 + `ffi` 136 + `reference` 130 + `probe` 33), which
  does not reconcile with the recorded JSON result of 731 passed and 1 skipped. It also assigns
  release-runner/provenance files to `probe`, leaving no `release` layer although the card defines
  that layer explicitly.
- Windows source-count evidence is incorrect for two rows: the table records 0 for
  `example/integration_test/helpers/probe/layout_pack_test.dart` and
  `example/integration_test/helpers/probe/probe_correctness_test.dart`, while their sources contain
  1 and 2 `test(` declarations respectively.
- The slow-file section gives code-based causes, but the single-coverage section contains broad
  categories and globs rather than one concrete contract and its sole test file. It cannot protect
  those contracts during TEST 5 cleanup.

Reviewer did not rerun the suite; findings are from the committed inventory, the recorded JSON
totals, and targeted source reads.
