# CI 2 — Linux: `camera_capture_native_test.dart` падает в CI
**Status:** BLOCKED · **Tier:** T2 · **Owner:** CLEAN 3 · **Depends On:** CLEAN 3 (тот же пул) · **Probe:** none

#### Goal
Фактическая карточка отказа post-merge CI (правило 4 `todo.md`). Отложенный CI этапов 4–5 прогнан тегом
`ci/all/CI-1` на SHA `af895ae` (код этапов 4–5 + триггеры CI 1). Linux-джоба упала.

- Workflow / run / job: `CI` ([run 37058238078](https://github.com/Anfet/yuv_ffi/actions/runs/37058238078)),
  джоба `linux-native-smoke`
  ([job 111008127165](https://github.com/Anfet/yuv_ffi/actions/runs/37058238078/job/111008127165)).
  Вторая джоба того же run, `bindings-regeneration`, зелёная.
- Упавший шаг: `Native correctness probes (linux desktop)`,
  `flutter drive … integration_test/camera_capture_native_test.dart … linux`.
- Фрагмент ошибки:
  ```text
  Failure in method: capture equals the geometry applied to its drawn frame while onFrame is still running
  The following UnimplementedError was thrown running a test:
  onCameraError() is not implemented.
  #0 CameraPlatform.onCameraError (package:camera_platform_interface/.../camera_platform.dart:103:5)
  #1 CameraController._initializeWithDescription (package:camera/src/camera_controller.dart:356:33)
  #2 main.<anonymous closure> (.../example/integration_test/camera_capture_native_test.dart:24:5)
  ```
- Известное: тест появился в CAMERA 2 (этап 4). CI этапа 4 был отложен, поэтому отказ виден впервые; причина —
  в Architect Decision.
- Критерий исправления: на Linux все `*_native_test.dart` проходят, тест камеры не пропускается; на остальных
  платформах — как раньше.

Engineer дал команду чинить (03.10.2026).

#### Architect Decision
Причина уточнена Reviewer (03.10.2026): дело не в Linux. Тест подменяет камеру `FakeCameraPlatform`
(`example/test/support/fake_camera.dart`), а `CameraController.initialize()` в `camera` 0.11.4 подписывается на
`CameraPlatform.onCameraError`, которого у фейка нет (базовый класс бросает `UnimplementedError`). В
`example/pubspec.lock` записан `camera` 0.11.0+2 — он `onCameraError` не вызывает, поэтому Windows, Android и macOS
проходят. На Linux (VM и CI) после `flutter create --platforms=linux .` + `pub get` резолвится 0.11.4.

1. **Фейк.** `FakeCameraPlatform` реализует `onCameraError(int cameraId)` — пустой поток (`const Stream.empty()`),
   как `onDeviceOrientationChanged`. Если после этого на 0.11.4 падает другой не реализованный метод — реализовать
   его так же (минимально, по факту падения) и перечислить в отчёте.
2. **Почему Linux берёт 0.11.4.** Выяснить на VM, что меняет резолв (`flutter create` или `pub get` на Linux) — по
   `diff` `example/pubspec.lock` до и после. Причину — в отчёт. `pubspec.lock` и `pubspec.yaml` не менять: если
   нужно — отдельная карточка.

#### Scope
- `example/test/support/fake_camera.dart`.

#### Constraints
- Тесты не пропускаются на Linux: фейк платформонезависим, тест должен проходить везде.
- `lib/`, native, `pubspec.*` не трогать.

#### Definition of Done
- [ ] На Linux VM (`todo.md`, «Окружение → Linux») все `example/integration_test/*_native_test.dart` проходят так же,
      как в джобе `linux-native-smoke`: `xvfb-run -a bash tool/ci/drive.sh integration_test/<target> linux`.
- [ ] На Windows `camera_capture_native_test.dart` проходит (в составе `tool/ci/windows.ps1`).
- [ ] Причина резолва 0.11.4 на Linux — в отчёте.

#### Validation
Ключи: `example/test/*` → `example`; проверка — на Linux VM и Windows. CI-тег не нужен: Linux проверяется на VM.

- `flutter analyze` в `example/`; `dart format --line-length 150` для изменённого файла.

#### Executor Report
#### Review
