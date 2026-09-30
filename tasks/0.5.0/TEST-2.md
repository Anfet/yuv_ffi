# TEST 2 — Теги тест-сьюта
**Status:** ARCHITECT_REQUIRED · **Tier:** T3 · **Execution Mode:** FAST · **Review Tier:** T2 · **Depends On:** — · **Rejection Count:** 0
**Было:** RA-60 (цикл 0.4.2).

#### Problem / Goal
Любая правка запускает всё: 700+ VM-тестов, 1188 проб, матрицу 119, все платформы. Нужно запускать только то, что относится к изменению.

#### Architect Decision
В `dart_test.yaml` описать теги и отметить каждый файл `@Tags([...])` по правилу:

| Тег | Файлы | Когда |
| --- | --- | --- |
| `smoke` | `native_packaging_smoke_test`, `loader_io_test`, `cmake_sources_test`, `apple_forwarder_sources_test`, `abi_symbol_manifest_test` | каждый push, секунды |
| `contract` | остальные `test/*.dart` | правки `lib/` |
| `probe` | `test/probe/**` | правки `lib/src/yuv/impl/**`, `src/**` |
| `reference` | `reference_*_test.dart` | правки `src/**`, конвертаций |
| `release` | provenance, dry-run, runner-тесты `test/probe/run_*` | только релизная проверка |

`flutter test` без аргументов = `smoke` + `contract` (`release`, `probe`, `reference` исключены по умолчанию через `dart_test.yaml`). Файл без тега — красный тест `test/tags_coverage_test.dart`.

#### Definition of Done
- [ ] Каждый файл имеет ровно один основной тег; `tags_coverage_test` зелёный
- [ ] `flutter test`, `--tags probe`, `--tags reference` дают в сумме то же число тестов, что прежний полный прогон

#### Executor Report
Остановлено до реализации: требования к selector по умолчанию конфликтуют с уже записанным решением Architect по поведению Flutter test runner.

- Эта карточка требует, чтобы `flutter test` без аргументов выбирал только `smoke + contract`, а явные `--tags probe` и `--tags reference` оставались рабочими.
- Решение в `docs/RA-60-architect:tasks/release-0.4.2/RA-60.md` фиксирует техническое ограничение: package selector `include_tags` пересекается с CLI `--tags`, а `exclude_tags` тоже блокирует исключённые теги при CLI-запуске. Поэтому Flutter не может получить селективный default и одновременно прямые селекторы отдельных исключённых групп из одной статической конфигурации.
- Тот Architect Decision предписывает оставить в `dart_test.yaml` только объявления тегов, считать `flutter test` полным прогоном, а обычный выборочный запуск задавать явно через `flutter test --tags 'smoke || contract'`; `tool/ci/vm.ps1` должен использовать этот явный selector. План 0.5.0 требует учитывать это решение, но текущая карточка не обновляет контракт по умолчанию.
- Текущая конфигурация `dart_test.yaml` на `dev` задаёт `exclude_tags: release`; она также исключает `release` из прямого запуска по тегу. Реализация без уточнения контракта нарушила бы либо Definition of Done этой карточки, либо записанное техническое решение.

Требуется обновить Architect Decision и Definition of Done этой карточки: принять полный `flutter test` как default и четыре явные непересекающиеся группы, либо выбрать иной способ запуска, который сохраняет оба требования. Код и тесты не менялись.
