# TEST 6 — Тихий вывод тестов и CI
**Status:** TODO · **Tier:** T3 · **Owner:** TEST 2 · **Depends On:** TEST 2

#### Goal
Сейчас `tool/ci/*` печатают всё: каждую строку `flutter test --reporter expanded`, вывод `pub get`, cmake,
`flutter drive`, диагностические `debugPrint` из тестов. Успешный прогон — сотни строк, провал в них теряется.
Нужен вывод по `D:\.projects\TEST GUIDELINES.md`: успех — коротко, провал — что упало, почему, ожидалось/получено.

#### Architect Decision
- **Репортер `tool/ci/test_report.dart`** — чистый Dart (`dart:io`, `dart:convert`, без `package:yuv_ffi`).
  Читает из stdin поток `flutter test --reporter json`.
  - Успех: строка на файл `<путь>  Passed  <число>`; затем итог `N/N passed, K skipped, 0 failed` и общее время.
  - Провал: для каждого упавшего теста — файл, полное имя теста, текст ошибки (в нём у `expect` уже есть
    Expected/Actual), первые кадры стека, относящиеся к `test/` или `lib/` (не больше пяти), и `print`-вывод
    именно этого теста. Вывод прошедших тестов не печатается никогда.
  - Ошибка загрузки файла (не компилируется) печатается как провал этого файла.
  - Код выхода: `0` только если событие `done` пришло с `success: true` и выполнен хотя бы один тест; иначе `1`.
    Этого достаточно, потому что в конвейере PowerShell и Bash решает код последней команды.
- **PowerShell:** в `tool/ci/_common.ps1` функция `Invoke-CiFlutterTest` (аргументы `flutter test` без
  `--reporter`): запускает `flutter test --reporter json @args`, передаёт поток в репортер, бросает исключение при
  ненулевом коде. Все вызовы `flutter test` в `tool/ci/*.ps1` переходят на неё; `--reporter expanded` удаляется.
- **Bash:** в `tool/ci/macos.sh` единственный вызов `flutter test` заменяется на
  `flutter test --reporter json … | dart tool/ci/test_report.dart` с `set -o pipefail`. Общий `_common.sh` не
  заводится, пока вызов один.
- **Прочие команды.** `Invoke-CiNativeCommand` собирает stdout и stderr команды; при успехе печатает одну строку
  `ok <команда> (<секунды> s)`, при провале — команду, код выхода и последние 80 строк вывода. Переменная
  окружения `YUV_CI_VERBOSE=1` возвращает полный вывод — для разбора сбоев, в CI не выставляется.
- **`flutter drive`.** `tool/ci/drive.ps1` и `drive.sh` сохраняют контракт (exit code `0` и строка
  `All tests passed`). При успехе печатается одна строка `PASS <target> on <device>`, при провале — вывод, начиная
  с первой строки с `FAILED`, `EXCEPTION` или `Error`, не больше 200 строк; если маркера нет — последние 200 строк.
- Тесты не меняются: их `print`/`debugPrint` скрывает репортер.

#### Scope
- Ветка `task/TEST-6` от `dev`, worktree `.worktrees/TEST-6`.
- Новые: `tool/ci/test_report.dart`, `test/ci_test_report_test.dart`, фикстуры `test/fixtures/test_report/*.jsonl`.
- Меняются: `tool/ci/_common.ps1`, `tool/ci/*.ps1` с вызовами `flutter test`, `tool/ci/macos.sh`,
  `tool/ci/drive.ps1`, `tool/ci/drive.sh`; эта карточка.

#### Constraints
- `.github/workflows/*` не меняются: они только вызывают `tool/ci/*`.
- Селекторы тегов из TEST 2 в скриптах сохраняются как есть.
- `test/ci_test_report_test.dart` получает тег по правилу TEST 2 и гоняет репортер на записанных фикстурах, без
  запуска `flutter test` внутри теста.
- Фикстуры — маленькие (десятки строк), записаны реальным `flutter test --reporter json` и обрезаны вручную.

#### Definition of Done
- [x] Успешный `tool/ci/vm.ps1`: строки `ok …` для служебных команд, строка на тестовый файл, итог; ни одного
      `debugPrint` из тестов (например, строки `YUV-11 native provenance`)
- [x] Негативный контроль VM: временно испорченный `expect` (не коммитится) → в выводе файл, имя теста,
      Expected/Actual; код выхода скрипта ненулевой
- [x] Негативный контроль загрузки: временная синтаксическая ошибка в тестовом файле → файл назван, код ненулевой
- [x] Негативный контроль `drive.ps1`: цель с падающим тестом → вывод от маркера провала, код ненулевой
- [x] `test/ci_test_report_test.dart` покрывает: всё прошло → код 0; есть провал → код 1 и блок провала;
      ошибка загрузки → код 1; ни одного теста → код 1
- [x] `macos.sh` проходит на Mac с тем же видом вывода

#### Validation
- Windows: `tool/ci/vm.ps1`, `tool/ci/windows.ps1`, `tool/ci/smoke.ps1`; негативные контроли из DoD — вывод в
  Executor Report.
- Mac через mac-runner: `bash tool/ci/macos.sh`.
- `flutter analyze`, `dart format --line-length 150` для новых Dart-файлов.

#### Executor Report

- Windows `vm.ps1`: 583/583 passed; служебные команды выведены короткими строками `ok`, успешные тесты — построчно по файлам, `debugPrint` скрыт.
- Windows `windows.ps1`: probe 15/15 (1 skipped), reference 123/123; Windows release сборка и оба drive-target прошли. `smoke.ps1` прошёл.
- Негативный VM assert-контроль вернул код 1 и блок с файлом, именем теста, Expected/Actual. Контроль синтаксической ошибки: `vm.ps1` остановился на `flutter analyze` с ненулевым кодом; прямой вызов `Invoke-CiFlutterTest` назвал файл и вывел диагностику загрузки с ненулевым кодом.
- Негативный `drive.ps1`: временный failing expect завершил прогон с кодом 1; в выводе от маркера `EXCEPTION` были Expected/Actual и причина теста.
- `test/ci_test_report_test.dart`: 4 теста прошли; `dart format --line-length 150` — без изменений. Финальный `vm.ps1` включает `flutter analyze`.
- Mac: `bash tool/ci/macos.sh` прошёл, включая packaging smoke 1/1, release build и оба drive-target.

#### Review

- **TODO (T2, 2026-10-01):** при общем падении репортёр печатает успешные файлы. В `tool/ci/test_report.dart:100-120` для каждого suite без `suite.failed` безусловно выводится `<path>  Passed …`, даже если другой suite содержит failure. Это противоречит Architect Decision: при провале «вывод прошедших тестов не печатается никогда». Текущая фикстура `failure.jsonl` содержит только один suite, а `ci_test_report_test.dart` не проверяет отсутствие такой строки, поэтому регрессия не обнаруживается.
- **Требуется:** печатать строки `Passed` только при полностью успешном прогоне; при общем провале оставлять блоки упавших тестов, итог и время. Добавить маленькую JSONL-фикстуру с успешным и упавшим suite и прямой тест, который подтверждает код 1, диагностический блок падения и отсутствие строки `Passed`/вывода успешного теста.
