# FIX 1 — Атомарность `applyPatch()` для внешней реализации `YuvImage`

**Status:** REVIEW · **Tier:** T2, Reviewer T1 · **Owner:** — · **Depends On:** — · **Probe:** windows+pixel3

**Base SHA:** `a2b679984e5ab4071820c873de82fffb5ec587b7`

#### Goal

Устранить частичную запись при некорректных плоскостях внешнего `implements YuvImage`. Контракт: любой отвергнутый `applyPatch()` оставляет байты, геометрию и ревизию получателя прежними; успешный вызов сохраняет padding и увеличивает ревизию один раз.

#### Architect Decision

1. Перед первой записью один раз получить списки плоскостей обеих картинок и проверить количество, высоту, row/pixel stride и доступность всех читаемых и записываемых байтов для каждой плоскости и строки. Проверка должна учитывать ширину сэмпла BGRA/NV12 и последний видимый сэмпл, а не только общую длину буфера. Использовать эти же снимки списков при копировании: повторный getter внешней реализации не должен менять проверенную структуру.
2. Сохранять существующие объекты плоскостей получателя и невидимые байты. Не переносить операцию на `applyPlanes()`: это заменит ссылки на плоскости, что не является контрактом `applyPatch()`.
3. Добавить узкий тест с внешним `implements YuvImage`: валидные размеры и формат I420, но отсутствующая или укороченная chroma-плоскость; убедиться, что ошибка возникла до записи Y и ревизия прежняя. Проверить успешный путь для внешней реализации и существующий тест padding. Не добавлять обязательный метод в интерфейс `YuvImage`.
4. Если внешний объект разделяет плоскость/буфер с получателем, не допустить изменения источника в обход контракта. Достаточно отклонить пересечение до записи; расширение не обещает in-place самовставку.

#### Scope

`lib/src/yuv/shared/yuv_patch.dart`, целевые тесты `test/yuv_image_patch_test.dart`; только необходимые правки рядом. Native C и generated bindings не трогать.

#### Constraints

- Нормальные I420/NV12/BGRA результаты, выравнивание chroma и правило odd edge не менять.
- Все проверки и временные выделения завершать до первой записи. Не принимать частичный результат как успех.
- Проба по AGENTS.md: Windows — Executor, Pixel 3 arm64 — Reviewer; armv7 требуется только если изменён `src/`.

#### Definition of Done

- Регрессионный тест воспроизводит отказ исходной реализации и проходит после исправления: Y и остальные байты, формат/размеры и ревизия не меняются.
- Успешные тесты для трёх форматов, padding и внешнего получателя проходят; ревизия растёт ровно один раз.
- Windows-проба имеет вердикт не `FAIL`; `SLOWER` объяснён или исправлен. Reviewer подтверждает Pixel 3 arm64.

#### Validation

- `dart format --line-length 150 <изменённые Dart-файлы>` и `dart analyze <изменённые Dart-файлы>`.
- `flutter test test/yuv_image_patch_test.dart test/public_surface_test.dart`.
- `pwsh -File tool/ci/windows.ps1`; Reviewer: `pwsh -File tool/probe/run_android.ps1 -Serial 8B1X11QLW` на Pixel 3 arm64 с фактическим вердиктом.
- В Executor Report: base/итоговый SHA, команды, exit code, счётчики/вердикты пробы и объяснение любого отклонения.

#### Executor Report

- Base SHA: `a2b679984e5ab4071820c873de82fffb5ec587b7`; implementation commit: `584a7ebcaa606367b299825a8f35b928236cb3c2`.
- `dart format --line-length 150 lib/src/yuv/shared/yuv_patch.dart test/yuv_image_patch_test.dart` — exit 0.
- `dart analyze lib/src/yuv/shared/yuv_patch.dart test/yuv_image_patch_test.dart` — exit 0, no issues.
- `pwsh -File tool/ci/windows.ps1` — exit 0; VM 134/134, Windows integration and probe targets passed, including `yuv_image_patch_test.dart`.
- `flutter test test/yuv_image_patch_test.dart test/public_surface_test.dart` — standalone exit 1 because the test process cannot locate `yuv_ffi.dll`; Windows CI wrapper passed both tests using its configured build environment.
- Added an external `implements YuvImage` regression with a missing chroma plane. Plane lists and all visible byte bounds are validated before writes; shared source/destination byte storage is rejected. Pixel 3 arm64 probe remains Reviewer validation per card.

#### Review
