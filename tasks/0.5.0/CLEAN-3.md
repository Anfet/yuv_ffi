# CLEAN 3 — Уборка example: экран редактора и камерный экран
**Status:** AWAITING_EXTERNAL · **Tier:** T2 · **Owner:** Executor · **Depends On:** — · **Probe:** windows

#### Goal
Example — витрина пакета, а `main.dart` (345 строк) собран до этапа 4: экран, состояние и все операции лежат в
`MyApp`, изображение показывается обходом `FittedBox` → `SizedBox(w×h)` → `YuvImageWidget(boxFit: none)` с вручную
построенной геометрией для рамки лица, подписи расходятся с действием («To Nv21» делает NV12), есть опечатки в
именах, закомментированный код и `logTimed`, который `await`-ит синхронные вызовы. Камерный экран смешивает
состояние камеры, обработку и разметку; кадр камеры импортируется двумя разными функциями. Задача — привести
example к текущему API пакета и пути показа этапа 4 без новой функциональности.

Этап 6 — первая задача этапа, этап открыт.

#### Architect Decision
1. **Показ в редакторе — путём камеры.** Изображение редактора показывается через `YuvFramePresenter(useShader: true)`
   и `YuvFrameView`: после каждой операции — `present(image)`; рамка лица строится по геометрии из
   `onGeometryChanged`, как в `YuvCameraView`. `FittedBox`/`SizedBox`/`YuvImageWidget` и ручная `YuvFrameGeometry`
   из редактора уходят. Презентер копирует кадр, поэтому редактор продолжает менять свой `YuvImage` на месте.
2. **Разделение main.** `main.dart` — только `main()` и `MaterialApp` (`YuvExampleApp`). Экран редактора —
   `example/lib/editor/editor_screen.dart`, панель операций — отдельный виджет рядом. Состояние (исходное
   изображение, рабочее, время операции, рамка лица) — в состоянии экрана; отдельного контроллера не вводить.
3. **Операции.**
   - Фильтры, поворот, отражение, обрезка — `apply*` над рабочим изображением; «Сброс» — `original.copy()`.
   - Конвертации — `toI420()` / `toNv12()` / `toBgra()`; подписи и tooltip'ы называют формат как есть (NV12).
   - Обрезка — `applyCrop` по прямоугольнику из долей стороны (15 %…85 % / 15 %…75 %, как сейчас);
     `widgets/crop_targets.dart` удалить.
   - Время операции — `Stopwatch` вокруг синхронного вызова; ML Kit остаётся асинхронным.
   - Задержки «для красоты» (`Future.delayed` после снимка в редакторе и на камерном экране) убрать.
4. **Камерный экран остаётся демо и стендом:** превью, рамка лица, снимок, закрыть, **строка FPS / shader и
   переключатель «heavy processing» сохраняются** (решение Engineer). Уборка — структура: `super.initState()` первым,
   без `controller`-геттера с `!`, типизированные `Future<void>`, оверлей (FPS, кнопки) — отдельным виджетом в том же
   файле, если `build` от этого становится читаемее. Поведение и tooltip'ы не меняются.
5. **Один импорт кадра камеры.** `CameraImage.toYuvImage()` из `ext.dart` и `importCameraImage()` из
   `camera/camera_image_import.dart` — две реализации одного. Остаётся одна, в `example/lib/camera/` (D-13); какая —
   решает Executor по потребителям (`camera_desktop_smoke_main.dart`, `integration_test/ios_bgra_camera_frame_test.dart`,
   тесты `example/test/`), тесты второй переносятся на оставшуюся или удаляются как дубли. Устаревший
   `// ignore: deprecated_member_use` с комментарием про `nv21` убрать. `ext.dart` оставляет только ML Kit
   (`toInputImage`).
6. **Тесты UI.** `integration_test/example_camera_flow_test.dart` и `desktop_camera_preview_smoke_test.dart` ищут
   `MyApp`, `YuvImageWidget`, tooltip'ы и `' fps'`. Tooltip'ы — контракт тестов и не меняются (кроме конвертации
   «To NV21» → «To NV12»); проверка показанного снимка переходит на `YuvFrameView`/презентер экрана редактора.
   Новый widget-тест редактора: операция меняет показанный кадр, «Сброс» возвращает исходный.

#### Scope
- `example/lib/main.dart`, `example/lib/editor/*`, `example/lib/camera_screen.dart`, `example/lib/ext.dart`,
  `example/lib/camera/camera_image_import.dart`, `example/lib/widgets/crop_targets.dart` (удаление).
- Потребители импорта кадра и тесты из решений 5–6: `example/lib/camera_desktop_smoke_main.dart`,
  `example/integration_test/*`, `example/test/*`.
- `example/README.md` — если в нём описан экран или кнопки.

#### Constraints
- `lib/` пакета, native, `example/lib/device_check/`, Web-источник камеры не трогать.
- Новой функциональности нет: набор операций, кнопок и камерный поток те же.

#### Definition of Done
- [ ] `main.dart` — точка входа и `MaterialApp`; редактор — `example/lib/editor/`; `crop_targets.dart` удалён.
- [ ] Редактор показывает изображение через `YuvFramePresenter`/`YuvFrameView`, рамка лица — по геометрии вида.
- [ ] Камерный экран сохраняет FPS / shader и «heavy processing»; структура по решению 4.
- [ ] Один импорт `CameraImage` в `example/lib/camera/`; `deprecated_member_use` в example нет.
- [ ] Тесты решений 6 обновлены и проходят; widget-тест редактора добавлен.

#### Validation
Ключи: `example/*` → `example`, `example/integration_test/*` → `all`.

- `dart format --line-length 150`; `flutter analyze` в `example/` — без замечаний.
- `pwsh -File tool/ci/example.ps1`, `pwsh -File tool/ci/windows.ps1`; `pwsh -File tool/ci/web.ps1` (example собирается
  и для Web).
- Ручной прогон на Windows: редактор (загрузка, операции, сброс), камерный экран (FPS, снимок → редактор).
- Probe `windows`: в составе `tool/ci/windows.ps1`.

#### Executor Report
Implemented on branch `all/CLEAN-3`:

- moved the editor from `main.dart` to `editor/editor_screen.dart`; it displays frames through `YuvFramePresenter` and `YuvFrameView`, and maps the face box through reported frame geometry;
- replaced in-place format conversion with `toI420()`, `toNv12()`, and `toBgra()`; reset copies the original frame;
- centralized camera-frame import in `camera/camera_image_import.dart`, removed the duplicate extension and `crop_targets.dart`, and updated all consumers/tests;
- retained camera FPS/shader and heavy-processing controls, removed the artificial capture delays, and extracted the camera overlay;
- updated integration consumers and added `test/editor/editor_screen_test.dart`.

Validation completed:

- `dart format --line-length 150 lib test integration_test` — PASS (only scoped files changed).
- `flutter analyze` in `example/` — PASS.
- with `C:\Users\Oleg-T\AppData\Local\Temp\yuv-ffi-windows\Release` on `PATH`: `flutter test test/editor/editor_screen_test.dart test/camera/camera_image_import_test.dart test/camera_image_to_yuv_image_padding_test.dart` — PASS, 6 tests.
- `pwsh -File tool/ci/windows.ps1` — native build and root `probe`/`reference`: PASS, 20/20 (1 skipped), no `SLOWER` verdict. The terminal has a 30-second per-process limit and did not return the following Windows example build/drive result.

External evidence still required before `REVIEW`:

- run `pwsh -File tool/ci/windows.ps1` to completion from the repository root;
- run `pwsh -File tool/ci/web.ps1` to completion from the repository root. Direct `flutter build web` generated `example/build/web/main.dart.js`, but the terminal cut off before a terminal `PASS`/`FAIL`, so it is not counted;
- manually verify on Windows: load an image, apply operations, reset; open camera, observe FPS/shader and heavy-processing control, capture into the editor.

#### Review
