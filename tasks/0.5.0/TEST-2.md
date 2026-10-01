# TEST 2 — Теги тест-сьюта
**Status:** ENGINEER_REQUIRED · **Tier:** T3 · **Execution Mode:** FAST · **Review Tier:** T2 · **Depends On:** — · **Rejection Count:** 0
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
- `dart_test.yaml`, `@Tags` в `test/**/*_test.dart`, новый `test/tags_coverage_test.dart`, `tool/ci/vm.ps1`;
  эта карточка.

#### Constraints
- Тела тестов не меняются — только аннотация `@Tags` и нужный для неё `library;`.
- Другие `tool/ci/*`, workflow и `example/` не меняются.
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
На ветке `task/TEST-2` изменения из `da7f699` уже присутствовали; повторный cherry-pick не выполнялся. В изолированном `$env:RUNNER_TEMP` собрана native DLL, `flutter pub get --no-example` и `flutter test test/tags_coverage_test.dart` завершились с кодом 0.

Результаты остальных команд Validation (`--reporter json`; число — видимые `testDone`, без скрытых загрузочных записей):

| Команда | Exit | Тесты | Результат |
| --- | ---: | ---: | --- |
| `flutter test --tags "smoke || contract"` | 0 | 569 | прошло |
| `flutter test --tags probe` | 1 | 16 | 1 ошибка, 1 пропуск |
| `flutter test --tags reference` | 0 | 130 | прошло |
| `flutter test --tags release` | 0 | 17 | прошло |
| `flutter test` | 1 | 732 | 1 ошибка, 1 пропуск |
| `pwsh -File tool/ci/vm.ps1` | 0 | — | прошло |
| `pwsh -File tool/ci/windows.ps1` | 1 | — | ошибка в probe-тесте |

Точная ошибка во всех трёх неуспешных прогонах: `test/probe/probe_copy_sync_test.dart:15`, `layout_pack_test.dart is out of sync`; исходный `test/probe/layout_pack_test.dart` начинается с `@Tags(['probe'])`, тогда как его копия `example/integration_test/helpers/probe/layout_pack_test.dart` не содержит этой аннотации. `windows.ps1` возвращает exit 1 по той же ошибке. Разница числа тестов от ожидаемых 733 не подтверждена: полный прогон завершил 732 видимых теста и имел одну ошибку и один пропуск.

Блокер: для зелёных `probe`, полного прогона и `windows.ps1` нужно согласовать изменение копии в `example/` с ограничением Scope этой карточки; на момент отчёта Executor статус был `BLOCKED`. Первые прогоны с некорректной PowerShell-обёрткой (Flutter получил пустой список аргументов) не учитывались.

#### Engineer Decision Required

**Вопрос:** разрешить ли точечную синхронизацию копии `example/integration_test/helpers/probe/layout_pack_test.dart` в рамках TEST 2 или сохранить запрет на правки `example/` и изменить контракт проверки копий?

**Известно:** `probe_copy_sync_test.dart` сравнивает файлы `test/probe` и `example/integration_test/helpers/probe` побайтово. Единственная разница у `layout_pack_test.dart` — добавленные в пакетный файл `@Tags(['probe'])` и пустая строка. `example/tool/copy_reference_fixtures.sh` копирует пакетные probe-файлы в `example/` целиком. Удаление тега из пакетного файла нарушит DoD о теге каждого `*_test.dart` и проверку `tags_coverage_test.dart`. Исправление внутри разрешённых аннотаций пакетных тестов невозможно.

| Вариант | Последствие |
| --- | --- |
| Разрешить добавить те же две строки в `example/integration_test/helpers/probe/layout_pack_test.dart` и включить этот путь как точечное исключение в Scope/Constraints | Сохраняет побайтовый контракт копий и все группы тестов; расширяет открытый scope на `example/`. Скрипт копирования уже производит нужный результат. |
| Оставить `example/` без изменений и разрешить `probe_copy_sync_test.dart` игнорировать только ведущую аннотацию тега при сравнении | Сохраняет запрет на `example/`, но требует изменения тела теста вопреки Constraints и ослабляет существующий контракт побайтовой идентичности. |

**Рекомендация Architect:** разрешить первый вариант как точечное исключение. После решения Engineer обновить Scope/Constraints и передать карточку свежему T3 Executor для синхронизации копии и повторения неуспешных проверок. До решения статус `ENGINEER_REQUIRED`.

#### Review
