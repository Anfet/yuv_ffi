# TEST 2 — Теги тест-сьюта
**Status:** TODO · **Tier:** T3 · **Execution Mode:** FAST · **Review Tier:** T2 · **Depends On:** — · **Rejection Count:** 1
**Было:** RA-60 (цикл 0.4.2).

#### Goal
Любая правка запускает всё: 730+ VM-тестов, пробы, эталонную матрицу. Нужно запускать только то, что относится к
изменению, и уметь отдельно запустить каждую группу.

#### Architect Decision
- **`flutter test` без аргументов — полный прогон.** Выборочный прогон вызывается явно. Причина — устройство
  test runner (`test_core` 0.6.17, `Configuration.merge`): `include_tags` из `dart_test.yaml` пересекается с
  `--tags` из командной строки, а `exclude_tags` объединяется. Поэтому при любом селекторе в `dart_test.yaml`
  явный `--tags probe` либо ничего не находит (`No tests match`, exit 79), либо не может включить исключённое.
  Пресеты (`-P`) сливаются так же и проблему не решают.
- `dart_test.yaml` объявляет пять тегов и не содержит `include_tags` и `exclude_tags` (нынешний
  `exclude_tags: release` удаляется).
- Каждый `*_test.dart` пакета получает ровно один основной `@Tags([...])`:

  | Тег | Файлы | Когда запускать |
  | --- | --- | --- |
  | `smoke` | `native_packaging_smoke_test`, `loader_io_test`, `cmake_sources_test`, `apple_forwarder_sources_test`, `abi_symbol_manifest_test` | каждый push, секунды |
  | `contract` | остальные `test/*.dart`, включая `test/web/**` и `tags_coverage_test.dart` | правки `lib/` |
  | `probe` | `test/probe/**`, кроме `release` | правки `lib/src/yuv/impl/**`, `src/**` |
  | `reference` | `reference_*_test.dart` | правки `src/**`, конвертаций |
  | `release` | provenance, dry-run, раннеры проб `test/probe/run_*` (приоритет над `probe`) | только релизная проверка |

- Команды:
  - `flutter test --tags "smoke || contract"` — обычный выборочный прогон;
  - `flutter test --tags probe`, `--tags reference`, `--tags release` — отдельные группы;
  - `flutter test` — полный прогон.
- `tool/ci/vm.ps1`: голый `flutter test` заменяется на `flutter test --tags "smoke || contract"`, иначе VM CI станет
  полным. `tool/ci/windows.ps1` (`--tags probe` и файл `reference_native_conversions_test`) не меняется: без
  селектора в `dart_test.yaml` он выбирает то же, что и сейчас, плюс `release`-файлы из `test/probe` больше не
  попадают под `--tags probe`.
- Файл без основного тега или с двумя основными находит `test/tags_coverage_test.dart` (читает исходники
  `test/**/*_test.dart`, `flutter test` внутри себя не запускает).
- **Готовая разметка уже есть:** коммит `da7f699` в ветке `task/RA-60` размечает 62 файла и добавляет
  `tags_coverage_test`. Тестовые файлы с `release/0.4.2` в `dev` не менялись, поэтому его можно перенести
  `git cherry-pick -n da7f699`, затем отбросить `tasks/release-0.4.2/RA-60.md` и привести `dart_test.yaml`
  к решению выше (там сейчас `include_tags`).

#### Scope
- Ветка `task/TEST-2` от `dev`, worktree `.worktrees/TEST-2` (уже существуют; продолжить в них).
- `dart_test.yaml`, `@Tags` в `test/**/*_test.dart`, новый `test/tags_coverage_test.dart`, `tool/ci/vm.ps1`; побайтовые копии в `example/integration_test/helpers/probe/` (см. Constraints);
  эта карточка.

#### Constraints
- Тела тестов не меняются — только аннотация `@Tags` и нужный для неё `library;`.
- Другие `tool/ci/*`, workflow и `example/` не меняются. Исключение (решение Engineer 01.10.2026): копии файлов `test/probe/` в `example/integration_test/helpers/probe/` синхронизируются с пакетными побайтово — `cp test/probe/<файл> example/integration_test/helpers/probe/<файл>` для каждого файла, где изменилась только аннотация `@Tags`. Другие правки `example/` запрещены.
- По D-9 `tool/ci/vm.ps1` проверяется локально тем же скриптом; ветка `ci/**` не нужна.

#### Definition of Done
- [ ] Каждый `*_test.dart` пакета имеет ровно один основной тег по таблице; `test/tags_coverage_test.dart` проходит
- [ ] `dart_test.yaml` объявляет пять тегов и не задаёт `include_tags` / `exclude_tags`
- [ ] Каждая из четырёх команд `"smoke || contract"`, `probe`, `reference`, `release` завершается с кодом 0 и выполняет
      хотя бы один тест
- [ ] На одном SHA число тестов полного `flutter test` равно сумме четырёх частей; отличие от базы TEST 1
      (731 passed, 1 skipped на `dev`) объяснено — ожидается +1 за `tags_coverage_test`
- [ ] `tool/ci/vm.ps1` выбирает `smoke || contract` и проходит; `tool/ci/windows.ps1` проходит

#### Validation
Windows, корень worktree, одна сессия PowerShell (DLL собирается как в `tool/ci/vm.ps1`); в каждом прогоне
считать завершённые тесты по JSON-выводу:

```powershell
. ./tool/ci/_common.ps1
Add-CiPath 'D:\.important\android-sdk\cmake\3.22.1\bin'
$dll = New-CiNativeBuild -Name 'yuv-ffi-test2-tags' -LibraryName 'yuv_ffi.dll'
Add-CiPath $dll
flutter pub get --no-example
flutter test test/tags_coverage_test.dart
flutter test --tags "smoke || contract" --reporter json
flutter test --tags probe --reporter json
flutter test --tags reference --reporter json
flutter test --tags release --reporter json
flutter test --reporter json
pwsh -File tool/ci/vm.ps1
pwsh -File tool/ci/windows.ps1
```

#### Executor Report

Свежий T3 Executor повторил проверки после отклонения на одном SHA `14d0e5966bf5243794e95812f5ce69e918fa1830` (до изменения этого отчёта). Синхронизированная копия `example/integration_test/helpers/probe/layout_pack_test.dart` и источник `test/probe/layout_pack_test.dart` имеют одинаковый SHA-256 `D6F3620B3197975170DF1FABC310789A523F19E37E79178144AE8674ECC20713`; изменения копии ограничены одобренной аннотацией `@Tags(['probe'])` и пустой строкой.

JSON count method: учитывать только события `testDone` с `hidden: false`; это завершённые тесты. `hidden: true` — служебные загрузчики файлов; skipped включается в completed и отдельно считается как skipped.

| Команда на SHA `14d0e5966bf5243794e95812f5ce69e918fa1830` | Exit | Completed | Passed | Skipped |
| --- | ---: | ---: | ---: | ---: |
| `flutter test --tags "smoke || contract" --reporter json` | 0 | 569 | 569 | 0 |
| `flutter test --tags probe --reporter json` | 0 | 16 | 15 | 1 |
| `flutter test --tags reference --reporter json` | 0 | 130 | 130 | 0 |
| `flutter test --tags release --reporter json` | 0 | 17 | 17 | 0 |
| **Sum of groups** | — | **732** | **731** | **1** |
| `flutter test --reporter json` | 0 | 732 | 731 | 1 |
| `flutter test test/tags_coverage_test.dart --reporter json` | 0 | 1 | 1 | 0 |

The four disjoint groups sum exactly to the full run: `569 + 16 + 130 + 17 = 732`. The full run has no failed tests. `tags_coverage_test.dart` is included in `smoke || contract` and also passed when run alone.

The baseline stated by TEST 1 is 731 passed and 1 skipped (732 completed). The observed full count on this TEST 2 SHA is also 731 passed and 1 skipped (732 completed), so the measured delta is 0. The card expects +1 for `tags_coverage_test.dart`, which would produce 733 completed, but that expected delta is not present in the same-SHA evidence. The added coverage test is confirmed passing, and the task diff contains no changes to existing test bodies; therefore this executor cannot explain the missing +1 or claim this DoD item satisfied. Status remains TODO pending reconciliation of the historical baseline / expected count; no Architect decision was made.

Additional DoD checks on the same code SHA:

- `pwsh -File tool/ci/vm.ps1` — exit 0; selected `smoke || contract` completed successfully. The script was given an isolated `RUNNER_TEMP` because the shared temp CMake cache referred to another worktree.
- `pwsh -File tool/ci/windows.ps1` — exit 0; probe selection and Windows integration targets passed, including the probe matrix (1,188 cases).
- `git diff --check` — passed; source and example copy SHA-256 values matched.

#### Engineer Decision

**Решено 01.10.2026:** вариант 1 — синхронизировать копию `layout_pack_test.dart` (и любую другую копию из `helpers/probe/`, если у её оригинала появилась только аннотация тега). Контракт побайтовой идентичности `probe_copy_sync_test` не ослабляется. Следующий шаг — свежий T3 Executor: синхронизация копии и повтор неуспешных проверок (`--tags probe`, полный `flutter test`, `tool/ci/windows.ps1`).

##### Запрос

**Вопрос:** разрешить ли точечную синхронизацию копии `example/integration_test/helpers/probe/layout_pack_test.dart` в рамках TEST 2 или сохранить запрет на правки `example/` и изменить контракт проверки копий?

**Известно:** `probe_copy_sync_test.dart` сравнивает файлы `test/probe` и `example/integration_test/helpers/probe` побайтово. Единственная разница у `layout_pack_test.dart` — добавленные в пакетный файл `@Tags(['probe'])` и пустая строка. `example/tool/copy_reference_fixtures.sh` копирует пакетные probe-файлы в `example/` целиком. Удаление тега из пакетного файла нарушит DoD о теге каждого `*_test.dart` и проверку `tags_coverage_test.dart`. Исправление внутри разрешённых аннотаций пакетных тестов невозможно.

| Вариант | Последствие |
| --- | --- |
| Разрешить добавить те же две строки в `example/integration_test/helpers/probe/layout_pack_test.dart` и включить этот путь как точечное исключение в Scope/Constraints | Сохраняет побайтовый контракт копий и все группы тестов; расширяет открытый scope на `example/`. Скрипт копирования уже производит нужный результат. |
| Оставить `example/` без изменений и разрешить `probe_copy_sync_test.dart` игнорировать только ведущую аннотацию тега при сравнении | Сохраняет запрет на `example/`, но требует изменения тела теста вопреки Constraints и ослабляет существующий контракт побайтовой идентичности. |

**Рекомендация Architect:** разрешить первый вариант как точечное исключение. После решения Engineer обновить Scope/Constraints и передать карточку свежему T3 Executor для синхронизации копии и повторения неуспешных проверок. До решения статус `ENGINEER_REQUIRED`.

#### Review

**T2 review, GPT-5.6 Terra, 01.10.2026: REJECTED.**

- `e9df413` follows the Engineer Decision narrowly: it changes only the permitted
  `example/integration_test/helpers/probe/layout_pack_test.dart` copy and this card.
  The source and copy resolve to the same blob `c5438ccae7b7c960b1e4d9b7a0c04f6cd4575c2b` on this SHA; no test body or
  `probe_copy_sync_test` change is present. The complete diff from task base `770fa18` changes test files only by their
  primary `@Tags` annotations (plus the specified `tags_coverage_test.dart`).
- The executor evidence covers the four tag selections and both CI scripts across the prior and fresh reports; after the
  synchronization, `probe`, full `flutter test`, and `tool/ci/windows.ps1` are reported green.
- DoD remains unproven: it requires explaining a `+1` difference from the stated TEST 1 baseline of `731 passed, 1 skipped`,
  but the full run is reported as exactly `731 passed, 1 skipped` (732 completed), and the report explicitly says the
  historical delta cannot be determined. Reconcile the baseline/count requirement with reproducible evidence (or obtain an
  Architect decision updating that requirement) before a fresh Executor returns the task to REVIEW.
