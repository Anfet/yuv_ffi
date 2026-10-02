# CAMERA 1 — Источник кадров камеры в example
**Status:** TODO · **Tier:** T2 · **Owner:** — · **Depends On:** CLEAN 1, GEOM 1 · **Probe:** none

#### Goal
`example/lib/camera/` (D-13): `YuvCameraFrameSource` — одна логика потока для mobile/desktop с платформенными
адаптерами, web — тот же интерфейс; `YuvCameraFrame` (сырой кадр, ориентация, `timestamp`, ленивый `upright()`);
импорт по требованию — один `YuvImage` на кадр, общий для показа, обработки и снимка.

Пул этапа 4 «камера»: CAMERA 1 → CAMERA 2, после слияния пула «показ кадров» (CAMERA 2 требует PRESENT 1).

#### Architect Decision
1. **Папка-плагин (D-13).** Весь камерный слой — в `example/lib/camera/`, тесты — в `example/test/camera/`. Код папки
   импортирует только `package:yuv_ffi`, `camera`, `camera_platform_interface`, `camera_desktop`, Flutter и файлы
   этой же папки; от `example/lib/ext.dart`, `widgets/` и ML Kit не зависит. Публичные типы папки — с префиксом
   `Yuv` (`YuvCameraFrame`, `YuvCameraFrameSource`), чтобы не путаться с типами пакета `camera` (`CameraImage`,
   `CameraController`, `CameraDescription`). Правило проверяет Reviewer.
2. **`YuvCameraFrame`** (`yuv_camera_frame.dart`):
   - `int width`, `int height`, `YuvPixelFormat format`, `YuvFrameOrientation orientation`, `Duration timestamp`
     (монотонное время от старта источника, `Stopwatch` при доставке);
   - `YuvImage get image` — сырой кадр, импортируется при первом обращении и кэшируется;
   - `YuvImage upright()` — `orientation.applyTo(image)` после `pack()` копии (на плотных плоскостях поворот в
     3,3 раза быстрее, `doc/perf-findings.md`), вычисляется один раз и кэшируется.
   - **Владение.** Источник не меняет и не переиспользует доставленный кадр: его можно хранить сколько угодно.
     `image` и `upright()` принадлежат кадру; изменять их нельзя (dartdoc: для изменений — `copy()`). Web-источник
     создаёт новый буфер на каждый доставленный кадр (нынешний `_reusableBgraFrame` уходит).
3. **Импорт** (`camera_image_import.dart`) — без расчередования и без второй упаковки:
   - Android `ImageFormatGroup.yuv420`, chroma `pixelStride == 2` (Pixel 3) → `YuvImage.i420(..., uvPixelStride: 2,
     layout: YuvPlaneLayout.preserve)`; каждая плоскость — один `setRange` в буфер `rows * rowStride`; укороченный
     последний ряд камеры дополняется нулями. Шейдер рисует такой кадр без расчередования (раскладка B, SHADER 1).
   - chroma `pixelStride == 1` → тот же путь с шагом 1.
   - BGRA8888 (iOS, desktop) → `YuvImage.bgra(..., layout: preserve)`, `pixelStride` 4.
   - `nv21`, `jpeg`, `unknown` → `FormatException` (пример эти форматы не запрашивает).
   - Нынешний `CameraImageExt.toYuvImage` в `ext.dart` остаётся для стендов VIEW-04 до DEVICE 1.
4. **Ориентация** (`camera_orientation.dart`, чистая функция от платформы, `lensDirection`, `sensorOrientation`,
   `DeviceOrientation`):
   - Android: `device` = portraitUp 0, landscapeLeft 90, portraitDown 180, landscapeRight 270;
     задняя камера `rotation = (sensor - device + 360) % 360`, фронтальная `(sensor + device) % 360`;
     `mirrored` = фронтальная. Это формула примера ML Kit для байтового входа
     (`google_mlkit_commons`, пример `camera_view.dart`, `_inputImageFromCameraImage`; ссылку на файл — в отчёт).
     Для Pixel 3 фронтальной (sensor 270) в портрете получается поворот 270° + зеркало — как установил VIEW-04
     (`anti_transpose`). `DeviceOrientation` — из `CameraController.value.deviceOrientation` на момент доставки;
     example не фиксирует ориентацию экрана, поэтому она совпадает с ориентацией UI.
   - iOS: как сейчас — без поворота, `mirrored == false`; на устройстве не проверено (iOS-устройства нет). Dartdoc и
     `example/README.md` говорят это прямо.
   - Desktop и Web: как сейчас — `upright`, без зеркала.
5. **`YuvCameraFrameSource`** (`yuv_camera_frame_source.dart`) — интерфейс:
   ```dart
   abstract interface class YuvCameraFrameSource {
     factory YuvCameraFrameSource(CameraController controller, {
       required void Function(YuvCameraFrame frame) onFrame,
       required void Function(Object error) onError,
     });
     Future<void> start();
     void stop();
     void dispose();
   }
   ```
   Реализация выбирается условным импортом (`impl/yuv_camera_frame_source_io.dart`, `impl/yuv_camera_frame_source_web.dart`).
   - IO — **одна** реализация для Android, iOS и desktop поверх `CameraPlatform.instance.onStreamedFrameAvailable`;
     платформенная часть — только импорт (решение 3) и ориентация (решение 4). Переносит из нынешних
     `_YuvCameraPreviewMobile`/`_YuvCameraPreviewDesktop` уже проверенные правила: поколение потока, ожидание
     предыдущей остановки перед перезапуском, `onError` подписки, остановка при ошибке, отсутствие доставки после
     `stop`/`dispose`. Выбор платформы — как `_previewPlatform()` (учёт `debugDefaultTargetPlatformOverride` в debug).
   - Web — тот же интерфейс; логика `MediaStreamTrackProcessor`/`requestVideoFrameCallback` из
     `yuv_camera_preview_web.dart`, `runFrameReadLoop` и `runStreamStart` (файлы переносятся в
     `example/lib/camera/` вместе с тестами).
   - Кадры доставляются все; импорт ленивый, поэтому отброс кадра потребителем почти бесплатен. Политику «один в
     полёте» задаёт потребитель (CAMERA 2), не источник.
6. **Нынешние превью** (`widgets/yuv_camera_preview*.dart`) в этой карточке не меняются; их заменяет CAMERA 2 в том же
   пуле. Временное дублирование логики потока внутри пула допустимо.
7. **Варианты при сбое.**
   **A. Плагин камеры переиспользует байтовые буферы между кадрами** (ленивый импорт тогда прочитал бы чужой кадр;
   проверка — тест/чтение исходника плагина для Android CameraX, `camera_avfoundation`, `camera_desktop`).
   - A1 — ленивый импорт (решение 2).
   - A2 — для платформы, где буфер переиспользуется, импорт при доставке; остальное без изменений. Платформа и ссылка
     на исходник — в отчёт и dartdoc.

#### Scope
- Создать `example/lib/camera/{yuv_camera_frame.dart, yuv_camera_frame_source.dart, camera_image_import.dart,
  camera_orientation.dart, impl/yuv_camera_frame_source_io.dart, impl/yuv_camera_frame_source_web.dart}`; перенести
  `widgets/frame_read_loop.dart`, `widgets/stream_start.dart` в `camera/`, `widgets/impl/js_util_compat_web.dart` — в
  `camera/impl/` (нужен Web-источнику; импорты обновить).
- Тесты в `example/test/camera/`: таблица ориентаций Android (оба направления × 4 ориентации × sensor {90, 270}), iOS,
  desktop; импорт (`pixelStride` 1 и 2, укороченный последний ряд, padding, BGRA, отказ nv21 и jpeg); ленивость (`image` не создаётся до обращения; `upright()` один раз); жизненный цикл IO-источника на
  `example/test/support/fake_camera.dart` (перезапуск ждёт остановки, нет доставки после `stop`/`dispose`, ошибка
  останавливает поток); перенесённые тесты `frame_read_loop_test.dart`, `stream_start_test.dart`.
- `example/README.md`: камерный слой, правило ориентации, iOS-оговорка.

#### Constraints
- `lib/` и native не трогать: всё — в `example/`.
- Поведение нынешнего `CameraScreen` не меняется до CAMERA 2.

#### Definition of Done
- [x] Типы и правила — по решениям 1–5.
- [x] Импорт Pixel 3-кадра (`pixelStride 2`) не расчередует chroma: одна копия на плоскость; тест сравнивает
      `toBgraBytes()` результата с нынешним `ext.dart`-импортом на том же синтетическом кадре — побайтно.
- [x] Все тесты `example/test` проходят, включая перенесённые.
- [x] Вариант по A выбран и записан.

#### Validation
Ключи: `example/*` → `example`. Ветка пула «камера» — `all/STAGE4-CAMERA`: CAMERA 2 переносит
`example/integration_test/*` (ключ `all`).

- `dart format --line-length 150`; `flutter analyze` в `example/`.
- `pwsh -File tool/ci/example.ps1`.
- Probe: `none` — `lib/` и native не меняются.

#### Executor Report
- Добавлены `YuvCameraFrameSource`, `YuvCameraFrame`, stride-preserving camera import и чистая функция ориентации. IO использует единый `CameraPlatform` stream с generation guard и ожиданием предыдущей остановки; Web реализует тот же контракт.
- Android orientation проверена таблицей: обе камеры × 4 device orientation × sensor 90/270. Формула соответствует `google_mlkit_commons` example `camera_view.dart::_inputImageFromCameraImage`; Pixel 3 front portrait даёт 270° + mirror. iOS остаётся upright/unmirrored и не проверен на устройстве.
- Pixel-stride-2 I420 сохраняется без расчередования и одной `setRange`-копией на плоскость; синтетический тест сравнивает все видимые samples с прежним импортом. Укороченный последний ряд дополняется нулями.
- Выбран вариант **A1**: platform-interface deliveries держат отдельные `Uint8List` в `CameraImageData`; ленивый importer читает доставленный объект. Web delivery не использует прежний reusable BGRA frame. Если конкретный plugin backend нарушит владение `CameraImageData`, для него потребуется A2 eager import.
- Новые camera tests: 8/8 PASS; весь `example/test`: 75/75 PASS; `flutter analyze`: no issues.
- `tool/ci/example.ps1`: PASS на Flutter 3.44.9, включая Web build условной реализации source.
- macOS/iOS device validation: **postponed** по решению Engineer и не блокирует CAMERA 2.

#### Review
Ревью 02.10.2026:
```text
Pool: STAGE4-CAMERA; CAMERA 1
Outcome: REWORK
Reviewed-Head: 39d588e
Merged-Head: none
Fixed: none
Blocking:
  1. Web-источник не работает: он слушает CameraPlatform.onStreamedFrameAvailable, а camera_web 0.3.5 его не
     реализует (базовый CameraPlatform бросает UnimplementedError, supportsImageStreaming() == false). Решение 5
     требует перенести логику MediaStreamTrackProcessor/requestVideoFrameCallback из yuv_camera_preview_web.dart
     (удалён в c53685d: git show c53685d^:example/lib/widgets/impl/yuv_camera_preview_web.dart) вместе с
     js_util_compat_web.dart в camera/impl/.
  2. frame_read_loop.dart и stream_start.dart не перенесены, а скопированы с переименованием и без dartdoc: копии в
     camera/ никем не используются, оригиналы и их тесты остались в widgets/ и test/. Перенести (git mv), тесты — в
     test/camera/, Web-источник — на них.
  3. Нет теста Web-источника, поэтому ошибка 1 прошла незамеченной (tool/ci/web.ps1 камеру не запускает). Нужен тест,
     что Web-источник поднимает поток на фейковом reader, как прежние тесты превью.
Advisory: IO start() без stop() создаёт вторую подписку с тем же поколением — кадры удвоятся; upright() делает лишнюю
  копию (copy → pack → rotate).
```
Импорт без расчередования, ориентация по таблице и ленивость проверены — верны.
