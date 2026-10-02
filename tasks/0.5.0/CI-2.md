# CI 2 — Linux: `camera_capture_native_test.dart` падает в CI
**Status:** ENGINEER_REQUIRED · **Tier:** — · **Owner:** Engineer · **Depends On:** — · **Probe:** —

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
- Известное: тест появился в CAMERA 2 (этап 4) и запускает плагин `camera`, у которого нет Linux-реализации.
  Локально Linux не проверялся (D-2), CI этапа 4 был отложен, поэтому отказ виден впервые.
- Критерий исправления: Linux-джоба `ci/linux/<метка>` зелёная, тест камеры на Linux не запускается или
  пропускается с причиной, на остальных платформах проходит, как раньше.

Расследование и исправление — только по команде Engineer (правило 4).

#### Architect Decision
#### Scope
#### Constraints
#### Definition of Done
#### Validation
#### Executor Report
#### Review
