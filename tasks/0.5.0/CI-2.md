# CI 2 — Linux: `camera_capture_native_test.dart` падает в CI
**Status:** ACCEPTED · **Tier:** T2 · **Owner:** STAGE6 · **Depends On:** — · **Probe:** none

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
03.10.2026:

- `FakeCameraPlatform.onCameraError(int)` реализован как отфильтрованный незакрывающийся поток
  `CameraErrorEvent`. `Stream.empty()` закрывался немедленно и на `camera` 0.11.4 приводил к
  `Bad state: No element`; других нереализованных методов не потребовалось.
- `dart format --line-length 150 example/test/support/fake_camera.dart` — PASS.
- `flutter analyze` в `example/` — PASS.
- `pwsh -NoProfile -Command "& ./tool/ci/drive.ps1 integration_test/camera_capture_native_test.dart windows --no-pub; ..."`
  — PASS, `CI2_WINDOWS_EXIT=0`. Предыдущий запуск `tool/ci/windows.ps1` не имел terminal result и не использован
  как доказательство.
- Linux VM, Flutter 3.44.9: все `example/integration_test/*_native_test.dart` прошли через
  `xvfb-run -a bash tool/ci/drive.sh integration_test/<target> linux`:
  `camera_capture_native_test.dart`, `presenter_shader_native_test.dart`, `probe_native_test.dart`,
  `shader_probe_native_test.dart`; итоговая строка удалённого запуска — `CI2_FULL_LINUX_PASS`.
- `flutter create --platforms=linux .` меняет `example/pubspec.lock`, в частности `camera` `0.11.0+2` → `0.11.4`
  и Flutter/Dart SDK bounds до 3.44; следующий `flutter pub get` lockfile не меняет. Локальные `pubspec.yaml` и
  `pubspec.lock` не менялись.

#### Review

- **ACCEPT** (Reviewer, 03.10.2026, `9046db9`, `d55fb7e`). `onCameraError` в фейке — отфильтрованный поток событий, а не
  `Stream.empty()`: пустой поток закрывается сразу, и `camera` 0.11.4 падал на `Bad state: No element` — отклонение от
  решения 1 обосновано и по существу то же (ошибок фейк не шлёт). Linux VM: все четыре `*_native_test.dart` прошли;
  Windows: тест камеры прошёл. Причина 0.11.4 на Linux: `flutter create --platforms=linux .` пересобирает
  `example/pubspec.lock` (camera 0.11.0+2 → 0.11.4) — Linux-джоба CI проверяет другие версии зависимостей, чем lock;
  это учесть в остатке CI 1. Проверено Reviewer: `flutter analyze` в `example/` — без замечаний.
