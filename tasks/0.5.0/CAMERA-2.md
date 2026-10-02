# CAMERA 2 — Виджеты камеры в example
**Status:** BLOCKED · **Tier:** T2 · **Owner:** CAMERA 1 · **Depends On:** CAMERA 1, PRESENT 1 · **Probe:** none

#### Goal
`YuvCameraView` (прямой показ на GPU; `onFrame` с прореживанием вне пути отрисовки; `capture()`; доступ к текущей
геометрии) и `YuvTransformView` (`transform(YuvCameraFrame) → YuvImage`). `CameraScreen` на новом API; детекция лиц на
живом превью; «снимок = видимое».

Пул этапа 4 «камера»: CAMERA 1 → CAMERA 2.

#### Architect Decision
1. **Расположение** — `example/lib/camera/` (D-13, правило импортов CAMERA 1). ML Kit и рамки лиц — вне папки, в
   `CameraScreen` и `widgets/`.
2. **`YuvCameraViewController`** (`ChangeNotifier`) — связь экрана с виджетом:
   `ValueListenable<YuvFrameGeometry?> get geometry` (текущая геометрия показа, из `YuvFrameView.onGeometryChanged`),
   `Future<YuvImage?> capture()`. Создаёт и `dispose`-ит владелец экрана. Камерой не управляет: открытие,
   разрешение, объектив и `dispose` камеры — у `CameraController` пакета `camera`. Это ручка виджета, как
   `ScrollController` у списка. Параметры виджета называются `cameraController` и `viewController`, чтобы их не путать.
3. **`YuvCameraView`**: `CameraController cameraController`, `YuvCameraViewController? viewController`,
   `YuvFrameFit fit = YuvFrameFit.cover`, `Alignment alignment`,
   `FutureOr<void> Function(YuvCameraFrame frame)? onFrame`, `Duration onFrameInterval = Duration(milliseconds: 200)`,
   `Widget Function(BuildContext, YuvFrameGeometry)? overlayBuilder` (слой поверх кадра, перестраивается при смене
   геометрии), `VoidCallback? onStreamStopped`.
   - Показ: `YuvCameraFrameSource` (CAMERA 1) → `YuvFramePresenter(useShader: true)` →
     `present(frame.image, orientation: frame.orientation)` → `YuvFrameView(fit: ...)`. Кадр, пришедший при
     `presenter.isBusy`, отбрасывается до импорта.
   - **`onFrame` вне пути отрисовки:** вызывается не чаще `onFrameInterval` и никогда, пока не завершился `Future`
     предыдущего вызова; показ не ждёт `onFrame`, а `onFrame` не ждёт показа. Получает тот же `YuvCameraFrame`, что
     показан или отброшен презентером, — кадр независим (владение по CAMERA 1). Ошибка `onFrame` — в
     `FlutterError.reportError`, поток не останавливается. Что и где делать с кадром — забота вызывающего;
     dartdoc одной фразой: синхронная тяжёлая работа в UI-изоляте останавливает и показ.
   - **`capture()`** — снимок видимого: ближайший кадр, который будет **нарисован** (подтверждение по
     `onFramePresented`, как в нынешнем `CameraScreen`), → `geometry.apply(frame.image)` с геометрией, по которой он
     нарисован. Поток остановлен или виджет удалён до отрисовки → `null`. Повторный вызов до завершения возвращает
     тот же `Future`.
   - Ошибка камеры: поток остановлен, текст ошибки вместо превью, `onStreamStopped` — как сейчас.
4. **`YuvTransformView`**: те же `cameraController`, `fit`, `alignment`, `overlayBuilder`, `onStreamStopped`, плюс обязательный
   `YuvImage Function(YuvCameraFrame frame) transform`. На каждый кадр, принятый незанятым презентером, вызывается
   `transform`, результат показывается `present(result)` (ориентация уже применена в `transform`, обычно через
   `frame.upright()`). Ошибка `transform` отбрасывает только этот кадр (нынешний контракт `presentCameraFrame`).
5. **`CameraScreen`** на `YuvCameraView`:
   - детекция лиц — только Android и iOS (ML Kit), через `onFrame`: ML Kit получает **сырой** кадр и
     `orientation.rotation` в `InputImageMetadata.rotation` (правило GEOM 1); `toInputImage` в `ext.dart` получает
     параметр поворота. Рамки — в upright; `overlayBuilder` рисует `MatrixUtils.transformRect(geometry.uprightToView, box)`;
     зеркало применяет геометрия;
   - кнопка снимка → `viewController.capture()` → `Navigator.pop(image)`, как сейчас;
   - отладочный переключатель «тяжёлая обработка 1 раз/с» — только пример использования `onFrame`: с интервалом 1 с
     `compute()` из `package:flutter/foundation.dart` выполняет `applyGaussianBlur(radius: 10, sigma: 10)` над
     `frame.upright()` (в изоляте сначала `YuvFfi.initialize()`; если так не работает — обработка в UI-изоляте,
     причина в отчёт). `compute`, а не `Isolate.run`: на Web изолятов нет, и `compute` там просто выполняется в
     основном потоке — превью на время обработки замирает, это ожидаемо и пишется в `example/README.md`; в углу — FPS (как
     `showDebugInfo` сейчас) и `shader: on/off` из `YuvFrameRenderer.hasShader`. Это стенд DEVICE 1.
6. **Удаление старого API:** `widgets/yuv_camera_preview.dart`, `widgets/impl/yuv_camera_preview_*.dart`,
   `widgets/present_camera_frame.dart` (если не остаётся пользователей). Проверки их тестов переносятся на новые
   виджеты: `camera_preview_lifecycle_test`, `desktop_camera_preview_test`, `camera_screen_capture_test`,
   `present_camera_frame_test`, integration `desktop_camera_preview_smoke_test`, `example_camera_flow_test`,
   `ios_bgra_camera_frame_test`, точка входа `camera_desktop_smoke_main.dart`. Ни одна проверенная семантика
   (поколения, остановка при ошибке, захват только нарисованного кадра, отказ от кадра остановленного потока) не
   теряется без записи в отчёте.

#### Scope
- Создать в `example/lib/camera/`: `yuv_camera_view.dart`, `yuv_transform_view.dart`,
  `yuv_camera_view_controller.dart`.
- `example/lib/camera_screen.dart`, `example/lib/ext.dart` (`toInputImage` с поворотом), `example/lib/main.dart`
  (если меняется вызов экрана), удаление по решению 6, перенос тестов.
- Тесты `example/test/camera/`: интервал и неперекрытие `onFrame`; `onFrame` не блокирует показ; `capture()` даёт
  кадр, который нарисован, и равен `geometry.apply` (сравнение байтов); `capture()` → `null` при остановке;
  `YuvTransformView` показывает результат `transform`; ошибки `onFrame`/`transform` не останавливают поток.
- `example/README.md`: виджеты камеры, правило ML Kit, стенд тяжёлой обработки.

#### Constraints
- `lib/` и native не трогать. Если для задачи нужно изменение пакета — `ARCHITECT_REQUIRED` с описанием.
- Web: `YuvCameraView` работает через Web-источник CAMERA 1 и BGRA-путь рендерера (шейдер на Web — WEB 1).

#### Definition of Done
- [ ] Виджеты и контроллер — по решениям 2–4; `CameraScreen` — по решению 5; старое API удалено по решению 6.
- [ ] Все `example/test` и integration-цели `tool/ci/example.ps1`/`windows.ps1` проходят.
- [ ] Pixel 3, debug или profile (проверка поведения, не скорости): превью в портрете и альбоме ориентировано верно,
      фронтальная камера отзеркалена, рамка лица совпадает с лицом в обеих ориентациях, снимок совпадает с видимым
      кадром. Скриншоты экрана и снимка — пути в отчёте (файлы вне репозитория).
- [ ] Windows desktop smoke (`camera_desktop_smoke_main.dart` или его замена) проходит.

#### Validation
Ключи: `example/*` → `example`; при изменении `example/integration_test/*` → `all`.

- `dart format --line-length 150`; `flutter analyze` в `example/`.
- `pwsh -File tool/ci/example.ps1`; при изменении integration-тестов ещё `pwsh -File tool/ci/windows.ps1`,
  `pwsh -File tool/ci/android.ps1`, Mac: `bash tool/ci/macos.sh`, `bash tool/ci/ios.sh`, `pwsh -File tool/ci/web.ps1`.
- Pixel 3: `flutter run --profile` или debug-сборка example, проверка из DoD.
- Probe: `none` — `lib/` и native не меняются.

#### Executor Report
#### Review
