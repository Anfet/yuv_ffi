# FIX 7 — Уборка следов удалённого API и ID задач
**Status:** IN_PROGRESS · **Tier:** T2, Reviewer T2 · **Owner:** Executor · **Depends On:** — · **Probe:** windows (понижено: в `lib/src/yuv/impl/**` меняются только комментарии)

**Base SHA:** `78eca6c6071004175431f58c27fc8101664d501b`

#### Goal

0.5.0 удалила совместимый API 0.2.4/0.4.0, но в коде остались его следы. В `lib/` — 72 комментария
`// ignore: deprecated_member_use_from_same_package` в 8 файлах, хотя deprecated-объявлений больше нет. Dartdoc и
комментарии описывают удалённый «legacy/public `nv21` label» как действующий, а `YuvImageProvider` ссылается на
«patch release». `test/public_surface_test.dart` описывает проверку deprecated API, которого больше нет. В
опубликованном example остались ID задач. Карточка включает бывший FOLLOWUP 1.

#### Независимый вердикт (04.10.2026)

**Согласен с уборкой как задачей точности документации и теста.** Подтверждены 72 подавления
`deprecated_member_use_from_same_package` в восьми файлах, устаревшее описание публичного `nv21` в `lib/` и
комментарии теста о deprecated API при его отсутствии. При этом упоминания `nv21` не все ошибочны: эталонные
хелперы и manifest фиксируют исторический порядок UV и сравнения; их смысл и данные сохраняются. В example
`YUV40_VARIANT` — имя входного `dart-define`, а не подпись для читателя: переименование изменило бы тестовый
контракт. Убирать следует ID из человеческих сообщений и комментариев, сохранив этот ключ и записав его как
допустимое исключение. Сообщения `YUV-40 MARKER` сейчас не разбираются скриптами в репозитории, но их смысловые
маркеры этапов пробы нужно сохранить.

#### Architect Decision

1. **`lib/`, кроме сгенерированных bindings:** удалить все `// ignore: deprecated_member_use_from_same_package`;
   `dart analyze` остаётся чистым.
2. **Комментарии и dartdoc о текущем поведении,** без истории удалённого API:
   - `lib/src/yuv/shared/yuv_abi_v1_constants.dart:16`, `yuv_abi_v1_image_transport.dart:30` — «`nv21` label»;
   - `yuv_codec.dart:297`, `yuv_geometry.dart:100` — «legacy nv21 data / entry points»;
   - `lib/src/widgets/yuv_image_widget.dart:58–62` — «patch release».
   Остальные места с `legacy`, `deprecated`, `0.3`, `0.4`, `nv21` в `lib/` найти через `rg` и поправить только там,
   где комментарий неверно описывает действующий публичный API; корректное описание текущих байтов и stride
   сохранить.
   Логику не менять. Если комментарий описывает механизм, оставшийся только ради удалённого API (например,
   `allowLargerNvChromaStride`), переписать комментарий о текущем поведении и записать находку в отчёт; код не трогать.
3. **`test/public_surface_test.dart`** (бывший FOLLOWUP 1): вводные комментарии описывают фактическую проверку —
   потребитель импортирует только `package:yuv_ffi/yuv_ffi.dart`, строит текущие форматы и реализует интерфейс снаружи.
   Убрать `ignore: deprecated_member_use` у действующих вызовов; тестовая реализация `copy({bool blank = false})` →
   `copy()`. Ссылки на 0.3.0/0.4.0 как на текущий API исправить. Тест не расширять.
4. **Опубликованный example** (`example/integration_test/`, `example/tool/`, `example/lib/`): убрать ID задач
   (`YUV-06`, `YUV-12`, `YUV-40` и подобные) из сообщений `debugPrint`, `reason:` и комментариев. Перед правкой
   сообщения — `rg` по `tool/`, `.github/`, `example/` и `test/`: если строку разбирает скрипт, сообщение не трогать
   и записать это в отчёт. Не переименовывать `YUV40_VARIANT` без отдельного решения о тестовом контракте;
   удалить ID из окружающего комментария. Сохранить смысловые маркеры шагов пробы при правке их текстовых префиксов.
   `example/assets/reference/**/manifest.json` не перегенерировать: текст F-012/YUV-44 — часть зафиксированного
   эталона; принятый остаток записать в отчёт.

#### Scope

`lib/` (только комментарии и `ignore`; `lib/src/functions/bindings/` не трогать), `test/public_surface_test.dart`,
`example/integration_test/`, `example/tool/`, `example/lib/` (только комментарии и текст сообщений). Удаление
`tasks/0.5.0/FOLLOWUP-1.md` выполнено при планировании.

#### Constraints

- Никаких изменений поведения, сигнатур и публичного API; исполняемые строки `lib/` не меняются.
- Эталоны, golden и baseline не меняются. `tool/`, `test_native/`, `.github/` не в архиве — вне scope.
- Сгенерированные bindings не правятся.

#### Definition of Done

- `rg -n 'deprecated_member_use' lib --glob '!**/bindings/**'` пуст.
- В `lib/` нет комментариев, которые описывают удалённый API как действующий; найденные остатки механизмов записаны.
- `public_surface_test.dart` соответствует текущему интерфейсу и проходит.
- В человеческих сообщениях и комментариях опубликованного example нет ID задач, кроме записанных исключений;
  машинные ключи и эталонные данные остаются совместимыми.

#### Validation

- `git diff <base>..HEAD -- lib` содержит только строки комментариев (проверить
  `git diff -U0 ... | rg '^[+-]' | rg -v '^[+-]\s*//'` — пусто, кроме заголовков diff).
- `dart format --line-length 150` изменённых Dart-файлов; `dart analyze lib test`; анализ example (`example.ps1`).
- `pwsh -File tool/ci/vm.ps1`, `pwsh -File tool/ci/windows.ps1`; `$env:FLUTTER_VERSION='3.44.9'; pwsh -File tool/ci/example.ps1`.
- Ключи `bash tool/ci/scope_guard.sh <base>` — выполнить все напечатанные (для `example/integration_test` — `web`).
- Reviewer: выборочно сверить diff `lib/` на отсутствие исполняемых изменений.

#### Executor Report

- Удалены устаревшие `deprecated_member_use_from_same_package` и неверные комментарии о текущем API; исполняемые
  строки `lib/` не менялись. Публичный surface test и тексты example приведены к текущему интерфейсу.
- Сохранены `YUV40_VARIANT`, смысловые маркеры этапов пробы и поле JSON `card: DEVICE-1` (его проверяют тесты).
  Исторические fixture/manifests F-012/YUV-44 не изменялись.
- PASS: `dart analyze lib test`; `flutter test test/public_surface_test.dart` (4); `vm.ps1` (636/636);
  `example.ps1`; `android.ps1`; `smoke.ps1`; `ios.sh` (5 integration targets); `macos.sh` (native targets,
  CocoaPods build/smoke). Web-проверка — `web.ps1` (64 integration, 119 reference, 1 camera), выполнена в FIX 6.
- Windows `windows.ps1`: один запуск завершился на очистке `SemanticsHandle` в неизменённом
  `shader_probe_native_test.dart`; повтор целевого drive прошёл, полный `windows.ps1` ранее прошёл в FIX 5.
- Linux-проба ожидает повторного запуска на доступной VM.

#### Review
