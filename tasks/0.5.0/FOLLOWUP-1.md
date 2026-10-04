# FOLLOWUP 1 — Актуализировать тест публичной поверхности

**Status:** BLOCKED · **Tier:** T2, Reviewer T2 · **Owner:** — · **Depends On:** RELEASE 1 · **Probe:** none (только комментарии и тестовый код)

**Base SHA:** — (Executor записывает SHA рабочей ветки после релизного гейта)

#### Goal

Убрать из `test/public_surface_test.dart` утверждение о проверке удалённого deprecated API и привести тестовую реализацию к текущей сигнатуре `YuvImage.copy()`.

#### Architect Decision

1. Обновить вводные комментарии так, чтобы они описывали фактическую проверку: потребитель импортирует только `package:yuv_ffi/yuv_ffi.dart`, строит текущие форматы и может реализовать интерфейс снаружи.
2. Удалить устаревшие `ignore: deprecated_member_use` вокруг действующих конструкторов и заменить `copy({bool blank = false})` на `copy()` у тестовой реализации. Не расширять тест на недоступные legacy символы.
3. Поискать в этом файле оставшиеся ссылки на 0.3.0/0.4.0 как на текущий API; исправить только неточные комментарии. Производственный код и публичный API не менять.

#### Scope

`test/public_surface_test.dart`.

#### Constraints

Неблокирующее замечание аудита; не задерживает RELEASE 1. Не менять тестовую семантику иных сценариев.

#### Definition of Done

- Комментарии и реализация соответствуют текущему интерфейсу, тест компилируется и проходит через публичный import.
- Нет `ignore` для отсутствующего deprecated вызова в изменённых местах.

#### Validation

- `dart format --line-length 150 test/public_surface_test.dart`.
- `flutter test test/public_surface_test.dart`; `dart analyze test/public_surface_test.dart`.
- `git diff --check <base>..HEAD`; SHA и exit code — в Executor Report.

#### Executor Report

#### Review
