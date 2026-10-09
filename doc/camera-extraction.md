# Карта выделения камеры: yuv_ffi 0.5.2 / yuv_camera 0.0.1

Основание: PREP 1 (`tasks/0.5.2/PREP-1.md`), D-35, раздел «Цель и границы цикла» в `todo.md`. Состояние кода — база
`dev` `b81bf2c` (`b81bf2c3f230a144fe391e485009ffa24e677438`). Карта читается как вход для Architect при нарезке
карточек этапа 1; переносов и правок кода она не содержит.

Как составлена. Прочитаны исходники и конфигурация (`example/lib`, `example/test`, `example/integration_test`,
`example/probe`, `example/test_driver`, `example/tool`, `example/assets`, `example/pubspec.*`, платформенные каталоги
примера, `tool/ci`, `.github/workflows`, корневые `test/`, `tool/probe`, документация). Пути из `.ignore`, generated
bindings и `build/` не читались. Тесты, сборки и CI не запускались: всё про поведение ниже — «по чтению кода»; где
написано «подтверждено документом», источник назван.

Обозначения действия: **оставить** — файл остаётся в `yuv_ffi` без изменений; **перенести** — уезжает в `yuv_camera`
целиком; **разделить** — часть утверждений остаётся, часть уезжает (перечислены).

## 1. Границы и зависимости

### Публичный API `yuv_camera 0.0.1`

Пять типов из `todo.md`: `YuvCameraFrame`, `YuvCameraFrameSource`, `YuvCameraView`, `YuvCameraViewController`,
`YuvTransformView`. Экспортирует их один файл `lib/yuv_camera.dart` (новый пакет — своя точка входа; существующие
barrel-файлы `yuv_ffi` не затрагиваются). Всё остальное — `lib/src/`:

| Внутреннее | Откуда | Кто использует |
| --- | --- | --- |
| `importCameraImage` | `camera/camera_image_import.dart` | `impl/…_io.dart`; тесты; `iOS`-проверка и desktop-диагностика примера |
| `cameraFrameOrientation` | `camera/camera_orientation.dart` | `impl/…_io.dart`; тест |
| `runFrameReadLoop`, `runStreamStart` | `camera/frame_read_loop.dart`, `camera/stream_start.dart` | `impl/…_web.dart`; тесты |
| `YuvCameraFrameSourceImpl` (io, web) | `camera/impl/` | фабрика `YuvCameraFrameSource` через условный импорт `dart.library.io` |

Внутренние функции сегодня тестируются и вызываются из примера по `package:yuv_ffi_example/camera/…`. После переноса их
видят только `package:yuv_camera/src/…`: пакетные тесты — штатно, пример (`camera_desktop_smoke_main.dart`,
`ios_bgra_camera_frame_test.dart`) — импортом из `src/`. Это допустимое исключение для примера и тестов (экспорт
внутренних функций ради тестов расширил бы API, а D-19/«Keep it simple» это запрещает).

### Зависимости

Камерный код импортирует из `yuv_ffi` только публичный `package:yuv_ffi/yuv_ffi.dart` (`rg 'package:yuv_ffi/src'` по
`example/lib` и `example/test` — пусто; `src/` берут только Web-тесты `example/integration_test`, которые остаются).
Использованные типы: `YuvImage`, `YuvPlane`, `YuvPlaneLayout`, `YuvPixelFormat`, `YuvFrameOrientation`,
`YuvImageRotation`, `YuvFramePresenter`, `YuvFrameView`, `YuvFrameGeometry`, `YuvFrameFit`, `YuvFfi`. Скрытой
зависимости камеры от внутренностей YUV нет. Обратной зависимости (YUV → камера) в `lib/` корня нет: слова «camera»/«ML
Kit» в `lib/` — только в dartdoc геометрии и виджета (`yuv_frame_geometry.dart`, `yuv_image_widget.dart`), они остаются.

| Пакет | Прямые зависимости | Dev |
| --- | --- | --- |
| `yuv_camera` | `flutter`, `yuv_ffi: ^0.5.2`, `camera: ^0.11.0+2`, `camera_platform_interface: ^2.10.0` (`CameraPlatform.instance` в io-источнике), `web: ^1.1.1` (web-источник) | `flutter_test`, `flutter_lints` |
| `yuv_camera/example` | `yuv_camera` (path `..`), `yuv_ffi`, `camera`, `camera_desktop: ^2.0.0`, `camera_platform_interface`, `google_mlkit_face_detection: ^0.13.1` | `flutter_test`, `integration_test`, `flutter_lints`, `image` (PNG в desktop-смоуке) |
| `yuv_ffi/example` после выноса | `flutter`, `yuv_ffi`, `cupertino_icons`, `image_picker`, `crypto` (probe-helpers) | `flutter_test`, `integration_test`, `flutter_lints`, `image` (`test_pattern_reference.dart`) |

Пределы версий `camera`/`camera_desktop`/ML Kit переносятся как есть (текущие `example/pubspec.yaml`); обновление
версий в цикл не входит. `sdk`/`flutter` в `yuv_camera` — как у YUV (D-24: Dart ^3.12.0, Flutter ≥3.44.0);
`camera_desktop 2.0.0` требует `^3.11.0` — совместимо.

Из `yuv_ffi/example` уходят: `camera`, `camera_desktop`, `camera_platform_interface`, `google_mlkit_face_detection`,
`web` (в примере его импортирует только `lib/camera/impl/yuv_camera_frame_source_web.dart`). `ffi` — кандидат на
удаление: в примере нет ни одного `dart:ffi`/`package:ffi`, а комментарий у зависимости («Camera frame benchmarks…»)
описывает несуществующие бенчмарки; подтвердить `rg` + `flutter analyze` в карточке. `pubspec.lock`, tracked
registrants и `Podfile.lock` пересоздаются инструментами (`flutter pub get`, `pod install`), руками не правятся.

## 2. Инвентаризация

### 2.1. `example/lib` (21 файл)

| Исходный путь | Действие | Назначение | Причина | Проверка |
| --- | --- | --- | --- | --- |
| `main.dart` | оставить | `yuv_ffi/example` | `YuvExampleApp` → `EditorScreen`; камеру не импортирует | `flutter analyze` примера |
| `editor/editor_screen.dart` | разделить | остаётся: загрузка, операции, `YuvFrameView`; уходят: кнопки «Device check» и «Take photo», `detectFace`, `faceBox`, `EditorOperation.faceDetection`, импорты `camera_screen`, `device_check_screen`, `ext`, `face_rect_paint`, ML Kit | todo: редактор остаётся «без распознавания лиц» | `editor_screen_test` (см. 2.2), `example.ps1` |
| `ext.dart` | перенести | `yuv_camera/example/lib/ext.dart` | ML Kit-адаптер `YuvImage.toInputImage` | `yuv_image_to_input_image_test` (3 теста) |
| `widgets/face_rect_paint.dart` | перенести | `yuv_camera/example/lib/widgets/` | после выноса его используют только камера, device-check и результат захвата | `flutter analyze` |
| `camera_screen.dart` | перенести | `yuv_camera/example/lib/` | камерный экран: `YuvCameraView`, ML Kit, blur-стенд, захват | сценарий C1–C4 (3.2), `analyze` |
| `camera_desktop_smoke_main.dart` | перенести | `yuv_camera/example/lib/` | ручная desktop-диагностика, использует `importCameraImage` | ручной запуск (4, строка 6) |
| `device_check_main.dart` | перенести | `yuv_camera/example/lib/` | точка входа device-check | ручной запуск (4, строка 7) |
| `device_check/device_check_screen.dart` | перенести | `yuv_camera/example/lib/device_check/` | камера + ML Kit + `compute(blurBgra)` | `device_check_screen_test` (4) |
| `device_check/device_check_report.dart` | перенести | там же | схема `DEVICE-1`, медиана, округление | `device_check_report_test` (1) |
| `camera/yuv_camera_frame.dart` | перенести | `yuv_camera/lib/src/` + экспорт | публичный тип | `yuv_camera_frame_test` (1) |
| `camera/yuv_camera_frame_source.dart` | перенести | `lib/src/` + экспорт | публичный тип, условный импорт impl | `yuv_camera_frame_source_test` (1) |
| `camera/yuv_camera_view.dart` | перенести | `lib/src/` + экспорт | публичный виджет | `yuv_camera_view_test` (4, из них 3 для view) |
| `camera/yuv_camera_view_controller.dart` | перенести | `lib/src/` + экспорт | публичный тип | `yuv_camera_view_controller_test` (1) |
| `camera/yuv_transform_view.dart` | перенести | `lib/src/` + экспорт | публичный виджет | `yuv_camera_view_test` (1 из 4) |
| `camera/camera_image_import.dart` | перенести | `lib/src/` (внутр.) | импорт кадра, `YuvPlaneLayout.preserve` | `camera_image_import_test` (4), iOS BGRA (3.7) |
| `camera/camera_orientation.dart` | перенести | `lib/src/` (внутр.) | ориентация кадра | `camera_orientation_test` (2) |
| `camera/frame_read_loop.dart` | перенести | `lib/src/` (внутр.) | цикл чтения web-потока | `frame_read_loop_test` (5) |
| `camera/stream_start.dart` | перенести | `lib/src/` (внутр.) | старт web-потока | `stream_start_test` (8) |
| `camera/impl/yuv_camera_frame_source_io.dart` | перенести | `lib/src/impl/` | io-источник через `CameraPlatform.instance` | `yuv_camera_frame_source_test`, `camera_capture_native_test` |
| `camera/impl/yuv_camera_frame_source_web.dart` | перенести | `lib/src/impl/` | web-источник (`MediaStreamTrackProcessor` + canvas) | `camera_source_web_smoke_test` (3.6) |
| `camera/heavy_blur.dart` | перенести | `yuv_camera/example/lib/` (не в API) | демонстрационное размытие для `camera_screen`/device-check | `analyze`; device-check |

При переносе меняются: все `package:yuv_ffi_example/…` на `package:yuv_camera/…` (пакет) или `package:<имя примера>/…`
(пример); строка `library: 'yuv_ffi example'` в трёх `FlutterErrorDetails` (`yuv_camera_view.dart` ×2,
`yuv_transform_view.dart` ×1) — в публичном пакете она вводит в заблуждение. После выноса в `yuv_camera/example`
нужен минимальный экран результата: показывает снятый кадр через `YuvFrameView` и кнопку распознавания лица на снятом
кадре (иначе теряется утверждение C4 из 3.2). Новых API он не вводит.

### 2.2. `example/test` (13 файлов, 35 тестов)

| Исходный путь | Тестов | Действие | Назначение | Причина / сохраняемые утверждения |
| --- | --- | --- | --- | --- |
| `camera/camera_image_import_test.dart` | 4 | перенести | `yuv_camera/example/test/camera/` | страйд chroma 2 сохраняется; усечённая плоскость добивается нулями; padded BGRA без перепаковки; неподдерживаемые форматы → `FormatException` |
| `camera/camera_orientation_test.dart` | 2 | перенести | то же | Android: формулы сенсор/устройство для обеих линз и четырёх ориентаций; iOS и desktop — upright |
| `camera/frame_read_loop_test.dart` | 5 | перенести | то же | кадр устаревшего чтения закрывается, не показывается; ошибки устаревшего источника не доходят; текущий поток сообщает ошибки и завершается по `done` |
| `camera/stream_start_test.dart` | 8 | перенести | то же | отложенные старты, замена старта, ошибки/разрешения текущего и устаревшего старта |
| `camera/yuv_camera_frame_source_test.dart` | 1 | перенести | то же | кадры до `stop`, ошибка текущего потока, повторный старт (использует `FakeCameraPlatform`) |
| `camera/yuv_camera_frame_test.dart` | 1 | перенести | то же | ленивый одноразовый импорт `image`/`upright()` |
| `camera/yuv_camera_view_controller_test.dart` | 1 | перенести | то же | `detach` не отцепляет более новый обработчик |
| `camera/yuv_camera_view_test.dart` | 4 | перенести | то же | троттлинг `onFrame` без наложений; `capture` → `null` при остановке; ошибка `onFrame` не останавливает источник; ошибка `transform` роняет один кадр (`YuvTransformView`) |
| `support/fake_camera.dart` | — | перенести | то же | `FakeCameraPlatform` и кадры; общий для двух тестов и одного integration (3.4). Содержит неиспользуемые помощники (`yuvFrame`, `shadeOfYuv`, `drawnImage`, `drawnShade`, `pumpUntil`, `settleDecodes`) — переносить как есть, чистка вне карты |
| `device_check/device_check_report_test.dart` | 1 | перенести | то же | схема `DEVICE-1`, `schema: 1`, FPS, медиана 200.0, округление, `skipped` |
| `device_check/device_check_screen_test.dart` | 4 | перенести | то же | пропуск 7 шагов + копирование JSON; ответ на вопрос шага; последний шаг ждёт ответа; в ландшафте нет `AppBar` (все четыре — `cameraEnabled: false`, без плагина) |
| `yuv_image_to_input_image_test.dart` | 3 | перенести | `yuv_camera/example/test/` | I420 и NV12 с padded/pixel-gap плоскостями → настоящий NV21 (Y, затем V,U) без байтов зазора; BGRA → плотный буфер, `bytesPerRow = width*4`; метаданные размера/поворота |
| `editor/editor_screen_test.dart` | 1 | **оставить** | `yuv_ffi/example` | операция меняет показанный кадр, `Reset` возвращает оригинал; камеры не касается. Добавить кейс `crop` (см. 3.2, C5) |

Итог: 34 из 35 тестов переезжают, 1 остаётся. Ни один тест не удаляется и не сокращается.

Наблюдение. Ни один скрипт и workflow не запускает `flutter test` в `example/` (`rg 'flutter test' tool .github` →
только корень: `vm.ps1`, `windows.ps1`, `ci.yml:134`, `macos.sh`). `example.ps1` делает `flutter analyze` и `flutter
build web` — тесты примера компилируются, но не исполняются. Следовательно, текущая гарантия для этих 35 тестов —
ручной запуск; перенос не должен её «улучшать» молча: первый прогон в новом окружении (гейт G1, раздел 5) — это и есть
подтверждение. Editor-тест вызывает `YuvFfi.initialize()` и `applyNegate()` в `flutter test`, то есть требует
native-библиотеку в `PATH` (по чтению; не запускалось). Камерные тесты `YuvFfi.initialize` не вызывают.

### 2.3. `example/integration_test`

Камерные и смешанные цели (подробности — раздел 3 и 4):

| Путь | Действие | Назначение |
| --- | --- | --- |
| `camera_capture_native_test.dart` | перенести | `yuv_camera/example/integration_test/` |
| `camera_source_web_smoke_test.dart` | перенести | то же |
| `ios_bgra_camera_frame_test.dart` | перенести | то же |
| `desktop_camera_preview_smoke_test.dart` | разделить → перенести целиком | то же; ссылки на `demo.YuvExampleApp`/`CameraScreen` заменяются на новый пример |
| `example_camera_flow_test.dart` | разделить | камерная часть → `yuv_camera/example/integration_test/`; редакторная часть (`crop`, `negate`) → `editor_screen_test` YUV |

Остаются в `yuv_ffi/example/integration_test` без изменений (камеры и ML Kit не касаются; проверено `rg`): все
`*_web_test.dart` (включая `all_web_test.dart`, `fake_loader_web_tests.dart`), `web_matrix_abort_test.dart`, `reference_web_conversions_test.dart`,
`probe_web_test.dart`, `probe_native_test.dart`, `probe_performance_test.dart`, `shader_probe_native_test.dart`,
`shader_probe_web_test.dart`, `presenter_shader_native_test.dart`, `native_app_runtime_smoke_test.dart` и каталог
`helpers/` (33 файла: probe, reference, `shader_probe_cases`, `yuv_frame_render_reference`). Операционные
probe/reference и тесты синтетического потока `YuvImage` (`presenter_shader_native_test`) — у YUV по Architect Decision 4.

### 2.4. Остальное в `example/`

| Путь | Действие | Назначение / причина |
| --- | --- | --- |
| `probe/{android_release_benchmark,windows_release_benchmark,release_probe}.dart` | оставить | операционные замеры YUV; камеры нет (`rg` пусто) |
| `test_driver/integration_test.dart` | оставить; копия в `yuv_camera/example` | нужен `flutter drive` любого integration target |
| `tool/copy_reference_fixtures.sh`, `assets/reference/**`, `assets/probe/golden.json` | оставить | ассеты YUV-референса; камерных ассетов нет |
| `analysis_options.yaml`, `.gitignore`, `.metadata` | оставить; шаблон для нового примера | общие |
| `pubspec.yaml` | разделить | см. раздел 1: убрать камерные зависимости, комментарии к ним и `ffi`-комментарий |
| `pubspec.lock` | оставить, пересоздать `flutter pub get` | изменение — следствие, не отдельная правка |
| `README.md` | разделить | остаются: запуск, Web, редактор. Уходят в README примера камеры: слой `lib/camera/`, `YuvCameraView`, ML Kit, раздел «Device check», абзац о симуляторе iOS 18.x (ML Kit), права камеры |

### 2.5. Платформенная конфигурация `example/`

Камерные настройки в YUV-примере (после выноса удаляются) и их аналог в примере камеры:

| Путь | Что камерного | YUV-пример | Пример камеры |
| --- | --- | --- | --- |
| `android/app/src/main/AndroidManifest.xml` | явных разрешений нет: `CAMERA`/`RECORD_AUDIO` приходят из манифеста `camera_android_camerax` (проверено в кэше pub) | без изменений | свой `applicationId`/`namespace` (напр. `com.example.yuv_camera_example`), прав не добавлять; проверить итоговый merged-манифест |
| `android/app/build.gradle` | `minSdkVersion 26` — это `minSdk` самого `yuv_ffi` (`android/build.gradle:63`), не камеры | без изменений | то же значение |
| `ios/Runner/Info.plist` | `NSCameraUsageDescription` («Just for testing») | удалить | добавить, с осмысленным текстом |
| `ios/Podfile` | `platform :ios, '15.5'`; `PERMISSION_CAMERA=1` в `post_install` (пакета `permission_handler` в `pubspec.lock` нет — макрос без потребителя) | на этапе 1 не менять без прогона `ios.sh` на Mac; решение о снижении платформы и удалении макроса — по результату этого прогона | `15.5` (ML Kit), макрос не переносить |
| `ios/Podfile.lock` | pods ML Kit (`GoogleMLKit`, `MLKit*`, `google_mlkit_*`) | пересоздаётся `pod install` (в `ios.sh`) | создаётся при первой сборке |
| `macos/Runner/Info.plist` | `NSCameraUsageDescription` | удалить | добавить |
| `macos/Runner/{DebugProfile,Release}.entitlements` | `com.apple.security.device.camera` | удалить | добавить |
| `macos/Flutter/GeneratedPluginRegistrant.swift` (tracked) | `import camera_desktop`, `CameraDesktopPlugin.register` | пересоздаётся `flutter pub get`/сборкой | создаётся |
| `windows/flutter/generated_plugin_registrant.{cc,h}`, `generated_plugins.cmake` (tracked) | `camera_desktop` | пересоздаются; имена файлов не меняются (на них ссылаются `web.ps1` и `tool/probe/run_*.ps1`) | создаются |
| `linux/` | каталога нет; `ci.yml` делает `flutter create --platforms=linux` | в `ci.yml` убрать `libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev` и комментарий VIEW-01A | те же apt-пакеты нужны для сборки `camera_desktop` (GStreamer) |
| `web/index.html`, `web/manifest.json` | камерных настроек нет; доступ к камере в браузере — HTTPS или localhost + разрешение сайта | без изменений | копия |
| `pubspec.yaml: flutter.config.enable-swift-package-manager: true` | относится к `yuv_ffi`, не к камере | оставить | оставить |

Не проверено и не обещается: снижение iOS-платформы YUV-примера ниже 15.5; снятие пина симулятора iOS 18.x в `ios.sh`
(комментарий там объясняет его ML Kit). Оба — только после прогона `ios.sh` на Mac; до тех пор пин остаётся, а
`yuv_camera/example` его наследует.

### 2.6. Корень: тесты, скрипты, CI, документация

| Путь | Что про камеру | Действие |
| --- | --- | --- |
| `test/pack_planes_native_equivalence_test.dart` | сам тест YUV-only (`@Tags(['contract'])`, `camera` не нужен); в комментарии ссылка на `example/test/camera_image_pack_planes_test.dart`, которого нет с коммита `40a877b` | оставить; ссылку на несуществующий файл поправить в карточке документов (только комментарий) |
| `test/yuv_frame_presenter_test.dart:203` | комментарий «A camera delivering four frames…» — синтетический поток | оставить |
| `test/probe/*` (`probe_copy_sync_test`, `android_release_benchmark_contract_test`) | следят за `example/integration_test/helpers/probe`, `example/assets/probe`, `example/probe` | оставить: эти пути не затрагиваются |
| `tool/ci/web.ps1:237`, `tool/ci/web.sh:263-266` | блок `camera_source_web_smoke_test` с `--use-fake-device-for-media-stream` | убрать блок (и лишний `Start-WebDriver`/`start_driver … stop_driver`) |
| `tool/ci/web.ps1:259`, `tool/ci/web.sh:284` | итоговая строка «…; camera smoke=1.» | убрать фрагмент `camera smoke=1`; остальные числа (14 / 64 / 119) от камеры не зависят: цель не входит в `assert_web_source_matrix` |
| `tool/ci/windows.ps1:38`, `android.ps1:109`, `macos.sh:79`, `ios.sh:67`, `.github/workflows/ci.yml` (Linux, шаг «Native correctness probes») | glob `*_native_test.dart` | не менять: после выноса `camera_capture_native_test.dart` из каталога набор уменьшается с 4 до 3 целей сам |
| `tool/ci/ios.sh:36-45` | пин iOS 18.x «из-за ML Kit» | оставить до проверки (см. 2.5) |
| `tool/ci/example.ps1` | `analyze` + `build web` примера | не менять; после выноса проверяет упрощённый пример |
| `tool/ci/scope_guard.sh` | правила путей; `example/integration_test/*` → `all`, `example/*` → `example` | не менять; для `yuv_camera` — собственная копия (раздел 6) |
| `.github/workflows/ci.yml` | Linux-шаг сборки примера с GStreamer | убрать apt-пакеты GStreamer и комментарий VIEW-01A |
| `README.md` (корень) | раздел «Frame geometry and ML Kit» — про геометрию, остаётся; таблица платформ, строки iOS и macOS: «camera», «device check», «Camera stream smoke» как ручные проверки YUV | переформулировать: камера и device-check проверяются в `yuv_camera`; в YUV остаются показ шейдера и операции |
| `doc/web-parity.md:30,66,102,111` | «camera smoke» как часть Web-доказательства CI | переформулировать: Web-доказательство YUV — без камеры; camera smoke учитывается в `yuv_camera` (D-27, только Chrome) |
| `doc/web-camera-yuv.md` | исследование цикла 0.5.0 (формат кадров веб-камеры); в первой строке путь `example/lib/camera/impl/yuv_camera_frame_source_web.dart`; на документ ссылается `doc/perf-findings.md:43` | оставить в YUV (опора перф-выводов); правка — только указатель на новый путь; вопрос «перейти ли источнику на `copyTo` без `format`» передать в план `yuv_camera` |
| `CHANGELOG.md` | исторические записи про камеру остаются; новая верхняя запись `0.5.2` | этап 1; версия — четыре места по D-14 |
| `AGENTS.md`, `COMPLETION.md`, `MACHINES.md` | камеры нет (CI 2/CI 3 в `COMPLETION.md` — история) | не менять |

## 3. Смешанные сценарии

### 3.1. Device-check

Состав: `DeviceCheckScreen` (7 шагов: `portrait_idle`, `portrait_heavy`, `landscape`, `face_portrait`,
`face_landscape`, `mirror`, `capture`), `DeviceCheckReport`/`DeviceCheckMeasurement` (схема `DEVICE-1`),
`blurBgra` через `compute`, ML Kit (`face_ratio`), точка входа `device_check_main.dart`. Весь код и 5 тестов переезжают.

| Утверждение | Где проверяется сейчас | Куда |
| --- | --- | --- |
| схема отчёта, FPS, медиана, округление | `device_check_report_test` | `yuv_camera/example/test/device_check/` |
| поток шагов, JSON в буфер, ответ на вопрос, финальный шаг ждёт ответа, ландшафт без `AppBar` | `device_check_screen_test` (4) | там же |
| на устройстве в release: `display_fps`, `shader: true`, `rotation`/`mirrored`, `blur_runs`/`blur_ms_median`, `face_ratio`, ответы, размер захвата | ручной запуск на Pixel 3 / iPhone | ручной запуск в `yuv_camera/example`, команда не меняется (раздел 4, строка 7) |

Что теряет YUV. Подтверждение «шейдер реально рисует на физическом устройстве в release» (`shader: true`; на iPhone —
APPLE 1) давал только device-check. Остальные YUV-утверждения покрыты своими проверками: скорость blur — Pixel 3
release baseline (`gaussian r10`, `doc/perf-findings.md`), корректность — probe 1188; шейдер против CPU —
`shader_probe_native_test`/`presenter_shader_native_test` в CI (debug, эмулятор/симулятор/desktop). Физический показ
шейдера в release остаётся в релизном гейте этапа 2 **через пару**: device-check `yuv_camera/example` на Pixel 3
(arm64, `adb install -r`) и iPhone с кандидатом `yuv_ffi 0.5.2` по локальной подмене. Нужна отдельная YUV-проба —
решение Engineer (раздел 7, Q2); рекомендация — не вводить.

### 3.2. Редактор, захват, ML Kit: `example_camera_flow_test`

Единственная цель, в которой камера, ML Kit и редактор в одном сценарии. Запускается вручную на устройстве с камерой и
лицом оператора (ни один скрипт её не вызывает). Утверждения разделяются так:

| № | Утверждение | Куда |
| --- | --- | --- |
| C1 | «Take photo» открывает камерный экран, превью готово (кнопка «Capture frame») | `yuv_camera/example/integration_test/camera_flow_test.dart` (имя предложено; цель ручная) |
| C2 | «Capture frame» закрывает экран и возвращает кадр на предыдущий экран с `YuvFrameView` | то же |
| C3 | снятый кадр — `bgra8888`, `pixelStride 4` (в сообщении — «iOS camera capture»; на Android кадр приходит I420, платформу запуска фиксирует карточка, утверждение не обобщается) | то же |
| C4 | распознавание лица на снятом кадре (путь `toInputImage` + `FaceDetector`) находит лицо | то же; кнопка на экране результата примера камеры |
| C5 | в редакторе `crop` уменьшает ширину и высоту, `Negate` меняет байты, без исключений | `yuv_ffi/example/test/editor/editor_screen_test.dart`: `Negate` уже есть; добавить `crop` (`image` берётся из `initialImage`, камера не нужна) |

Рекомендация по C5: расширить существующий widget-тест, а не заводить новую цель. Если Engineer хочет, чтобы C5
выполнялся в CI, он должен стать `*_native_test.dart` (попадёт в glob) — это расширение CI, не перенос; без решения
остаётся ручным, как сейчас.

### 3.3. ML Kit-конвертация

`ext.dart` (`toInputImage`: I420/NV12 → NV21 `Y + VU`, BGRA → плотный буфер) используется на границе ML Kit (запись
памяти CLEAN 3: импорт камеры сохраняет страйды, плотная упаковка — только здесь) и после выноса редактором не
используется. Файл и `yuv_image_to_input_image_test` (3 теста) переезжают вместе в `yuv_camera/example`. Утверждения
теста (нет байтов зазора/padding в выводе, порядок V,U, `bytesPerRow`, размер и поворот в метаданных) сохраняются
дословно. Тест не использует камеру, но использует `google_mlkit_face_detection`, поэтому в YUV остаться не может.

### 3.4. Camera capture (`camera_capture_native_test`)

Цель использует `FakeCameraPlatform` (`../test/support/fake_camera.dart`) и не требует камеры; запускается в CI на всех
native-платформах (glob `*_native_test.dart`). Утверждение: `capture()` равен `geometry.apply()` для показанного
кадра, пока `onFrame` не завершился. Переносится целиком, вместе с `fake_camera.dart` (общий с двумя unit-тестами).
Расположение `fake_camera.dart` и тестов: рекомендуется перенос «путь в путь» (`example/test/…` и
`example/integration_test/…` внутри `yuv_camera/example`), чтобы относительный импорт `../test/support/fake_camera.dart`
и запуск `flutter test` из каталога примера не менялись. Перенос тестов в корневой `test/` пакета возможен позже; он
потребовал бы второй копии `fake_camera.dart` или кросс-пакетного относительного импорта.

### 3.5. Desktop smoke

Две ручные цели с реальной камерой, не в CI:

- `camera_desktop_smoke_main.dart` (`flutter run -t lib/camera_desktop_smoke_main.dart -d windows|macos|linux`):
  `availableCameras` → пять кадров через `CameraPlatform.instance.onStreamedFrameAvailable` → `importCameraImage` +
  `toBgraBytes()` → чистая остановка; вердикт — `SMOKE COMPLETE` или `SMOKE FAILED` + `exit(1)`. Весь файл — камера;
  переезжает (импорт `importCameraImage` — из `package:yuv_camera/src/…`). Утверждение «`toBgraBytes()` работает на кадре,
  импортированном из камеры» — единственное YUV-касание; операция проверяется в YUV своими тестами.
- `desktop_camera_preview_smoke_test.dart` (`flutter test integration_test/… -d windows --dart-define=SMOKE_OUT=<dir>`):
  D1 превью рисует >10 различных кадров за 6 с; D2 кадры превью не попадают в `ImageCache` (`currentSize + live +
  pending == 0`); D3 `capture` возвращает ровно один из двух следующих нарисованных кадров; D4 снимок — `bgra8888`;
  D5 `takeException()` пуст. Все пять утверждений остаются вместе в `yuv_camera/example`. D2 — свойство презентера YUV,
  которое ни один тест YUV не проверяет (`rg ImageCache` в `test/` пусто); оно сохраняется смоуком камеры. Дублировать его
  синтетическим тестом презентера в YUV можно, но не требуется для переноса.

Подтверждено документами: macOS со встроенной камерой (APPLE 1; README, таблица платформ). Windows: цель написана
для `-d windows`, но README ручной проверки Windows не заявляет (колонка «—»), другого подтверждения в документах не
найдено — не заявлять. Linux-камера не проверялась и не заявляется.

### 3.6. Web camera source

`camera_source_web_smoke_test` (CI: `web.sh` на Mac, локально — `web.ps1`; фейковая камера Chrome): `availableCameras`
непуст; `CameraController` инициализируется; `YuvCameraFrameSource` отдаёт кадр с `width/height > 0` и
`image.toBgraBytes()` не нулевой; после `dispose` кадры прекращаются. Это camera-утверждения плюс одно касание YUV
(Web-backend выполняет `toBgraBytes` на импортированном кадре). Переезжает целиком в `yuv_camera`; Web-backend YUV
проверяется своими 14 источниками. Ограничения сохраняются: только сборка JavaScript в Chrome (в `web.*` у цели нет
`--wasm`), Safari и Firefox не проверены (D-27), `MediaStreamTrackProcessor` недоступен вне Chromium, там срабатывает
canvas-путь — он не проверен. Юнит-проверки гонок web-потока (`frame_read_loop_test`, `stream_start_test`) — чистый Dart
и идут в VM.

### 3.7. iOS BGRA import

`ios_bgra_camera_frame_test`: padded BGRA кадр (2×2, `bytesPerRow 12`, две строки с 4 байтами padding, `bytesPerPixel:
null`, как у iOS-плагина) → `importCameraImage` сохраняет страйды (`rowStride 12`, `pixelStride 4`), а `toBgraBytes()`
возвращает ровно 16 видимых байт без padding. Первая часть — камера, вторая — свойство YUV `toBgraBytes()` с padding,
у которого есть собственные проверки в YUV (`yuv_bgra_pixel_gap_test`, `padded_bgra_constructor_web_test`,
`wasm_parity_edge_cases_web_test`). Цель целиком переезжает в `yuv_camera/example/integration_test/`. Сейчас она не
попадает ни в один glob (`_native_test.dart` в имени нет) и не вызывается скриптами — это ручная цель; сделать ли её
`*_native_test` — решение при нарезке (тогда она добавится в проверки всех native-платформ, это расширение). Название
привязано к iOS, но кода iOS-специфичного нет: по чтению тест исполним на любой native-платформе.

iOS-ориентация (расхождение источников, требует подтверждения Engineer, раздел 7, Q3). Dartdoc `YuvCameraFrame` говорит:
«iOS frames are currently treated as upright and unmirrored; that rule has not been device-verified». Но отчёт APPLE 1
(`git show 02a0796:tasks/0.5.0/APPLE-1.md`, 04.10.2026) фиксирует проверку на физическом iPhone (iOS 18.7): плагин сам
поворачивает кадр (480×640 портрет, 640×480 альбом), фронтальная камера зеркалится, ответы `landscape`/`mirror` — да,
`capture` 418×640; `example/README.md` и корневой README ссылаются на это. Dartdoc устарел относительно README. Граница
проверенного по APPLE 1: один iPhone, iOS 18.7, фронтальная камера (device-check выбирает фронтальную), портрет и
альбом; задняя камера, iPad, другие версии iOS — не подтверждены. В документации `yuv_camera` формулировать только эту
границу; код `cameraFrameOrientation` (iOS → upright) не менять.

### 3.8. Сравнения способов импорта

Тестов, сравнивающих способы импорта (packed/padded), в `example/` нет: `camera_image_pack_planes_test.dart` и
`camera_image_to_yuv_image_padding_test.dart` удалены в `40a877b` («Restored camera frame import strides»). Оставшиеся
утверждения распределены так: камерная сторона (страйды сохраняются, усечение, форматы) — `camera_image_import_test` и
`ios_bgra_camera_frame_test`, переезжают; YUV-сторона (padded и tight дают побайтно одинаковый результат
`toBgraBytes`/`applyRotation`, I420/NV12/BGRA, нечётные размеры) — корневой
`test/pack_planes_native_equivalence_test.dart` без зависимости от `camera`, остаётся. Ссылка на удалённый файл в
комментарии этого теста — устаревшая (2.6).

## 4. Integration-цели: вызовы, окружение, будущая команда

PASS везде определяется скриптами `drive.ps1`/`drive.sh`: exit 0 **и** строка `All tests passed` (AGENTS.md, раздел
CI); `flutter drive` напрямую не вызывать. Тот же критерий переносится.

| № | Цель | Сейчас вызывает | Окружение сейчас | Будущая команда (из `yuv_camera`) | Платформы и пределы |
| --- | --- | --- | --- | --- | --- |
| 1 | `camera_capture_native_test` | glob `*_native_test.dart` в `windows.ps1` (release-сборка), `android.ps1` (эмулятор `Tablet`, x86_64 API 35), `macos.sh`, `ios.sh` (симулятор iOS 18.x), `ci.yml` Linux (`xvfb-run`) | без камеры (fake-платформа) | те же команды в `tool/ci/*` репозитория `yuv_camera`, cwd `example`, цель `integration_test/camera_capture_native_test.dart` | Windows, Android-эмулятор, macOS, iOS-симулятор, Linux — как сейчас; на Linux сборке нужны GStreamer-пакеты |
| 2 | `camera_source_web_smoke_test` | `web.ps1:237` (Windows, Chrome + ChromeDriver), `web.sh:263` (Mac, `ci-web.yml`); флаги `--use-fake-device-for-media-stream --use-fake-ui-for-media-stream` | Chrome 154, JavaScript-сборка | `web.ps1`/`web.sh` `yuv_camera`: `pub get`, ChromeDriver, `drive` этой цели с теми же флагами | только Chrome/JS; `--wasm` не запускается; Mac-раннер для CI, Windows — локально |
| 3 | `ios_bgra_camera_frame_test` | никто (ручная) | iOS-симулятор/устройство или любая native-платформа | `bash tool/ci/drive.sh integration_test/ios_bgra_camera_frame_test.dart <device>` из `yuv_camera` | платформа не ограничена кодом |
| 4 | `example_camera_flow_test` | никто (ручная) | физическое устройство с камерой, лицо оператора, ML Kit (Android/iOS) | `drive` C1–C4 из `yuv_camera/example`; C5 — `flutter test test/editor/editor_screen_test.dart` в `yuv_ffi/example` | ML Kit лица — только Android/iOS (`_supportsFaceDetection`) |
| 5 | `desktop_camera_preview_smoke_test` | никто (ручная; в шапке `flutter test … -d windows`) | desktop с камерой | та же команда в `yuv_camera/example` | подтверждена macOS (встроенная камера, APPLE 1); Windows — см. 3.5; Linux не проверялся |
| 6 | `camera_desktop_smoke_main.dart` | никто (ручная) | desktop с камерой | `flutter run -t lib/camera_desktop_smoke_main.dart -d <windows\|macos\|linux>` | вердикт — `SMOKE COMPLETE` / `exit(1)` |
| 7 | `device_check_main.dart` | никто (ручная) | Pixel 3 (`8B1X11QLW`, `adb install -r`, release) и iPhone | `flutter run --release -d <id> -t lib/device_check_main.dart --dart-define=GIT_SHA=$(git rev-parse --short HEAD)` из `yuv_camera/example` | PASS: все 7 шагов пройдены, JSON скопирован, ответы «да»; решение по итогам — Reviewer/Engineer |
| 8 | `flutter test` примера (35 тестов) | никто | любая машина с Flutter (editor-тест — ещё native-библиотека в `PATH`) | `flutter test` в `yuv_camera/example` — 34 теста; в `yuv_ffi/example` — 1 (+`crop`) | при переносе первый прогон — гейт G1 |

Нумерация строк — только для ссылок внутри документа; в карточках будут свои ID.

Что меняется в подсчётах и сообщениях CI при переносе (только эти места):

- `web.ps1:259` и `web.sh:284`: убрать `camera smoke=1` (числа `sources=14`, `integration cases=64`, `reference matrix=119`
  не меняются).
- Набор `*_native_test.dart` у YUV: 4 → 3 цели (`probe_native`, `shader_probe_native`, `presenter_shader_native`); код
  скриптов не меняется, счётчиков в сообщениях у этих скриптов нет.
- Отчёты и `doc/web-parity.md` ссылаются на «camera smoke» как часть Web-доказательства — переформулировать (2.6).
- У `yuv_camera` свои сообщения: счётчики определит карточка скриптов.

## 5. Порядок переноса

1. **Каркас `yuv_camera` без правок YUV.** Локальный checkout (раздел 6), `pubspec.yaml`, `analysis_options`, `AGENTS.md`,
   `todo.md`, `.memory/`, `.gitignore` (с `pubspec_overrides.yaml`), `lib/yuv_camera.dart` с пятью экспортами.
2. **Копирование, не перенос.** Камерные файлы в `lib/src/`, пример со своими раннерами (`flutter create`, затем
   настройки раздела 2.5), экран результата, тесты и integration-цели путём в путь; правка импортов. Исходники в
   `yuv_ffi` пока не трогаются. Локальная подмена: `example/pubspec_overrides.yaml` и корневой
   `pubspec_overrides.yaml` с `path` на `D:\.projects\yuv_ffi` (прецедент: `tool/probe/run_*.ps1` создают
   `example/pubspec_overrides.yaml` на время прогона).
3. **Скрипты и CI `yuv_camera`.** Копии `_common.ps1`, `drive.ps1`/`drive.sh`, `scope_guard.sh`, `web.*`, платформенных
   скриптов — только для целей камеры; native-сборка YUV (`New-CiNativeBuild`, CMake в `PATH`) не нужна: библиотека
   собирается вместе с приложением как плагин.
4. **Гейт G1: подтверждение в новом окружении.** В `yuv_camera`: `flutter analyze`; `flutter test` — **34/34** (26
   камерных + 5 device-check + 3 `toInputImage`); `camera_capture_native_test` на Windows (release) и Android-эмуляторе;
   `camera_source_web_smoke_test` в Chrome (локально `web.ps1`-аналог); сборка примера для Windows/macOS/iOS/Linux по
   доступности; ручные цели 3, 5, 6, 7 — по правилам Reviewer/Engineer перед релизным гейтом, не перед удалением из YUV.
   Минимум для удаления: analyze + 34/34 + цели 1 и 2 зелёные, сравнение чисел с разделом 2.2 записано в карточке.
5. **Удаление из `yuv_ffi`, только после G1.** Одна карточка (или две): удалить перенесённые файлы раздела 2.1–2.3;
   изменить `editor_screen.dart` и добавить кейс `crop` (3.2, C5); убрать зависимости и платформенные настройки (2.5);
   пересоздать `pubspec.lock`, tracked registrants, `Podfile.lock` инструментами; поправить `web.*`, `ci.yml`,
   документы (2.6); версия 0.5.2 в четырёх местах (D-14) и верхняя запись `CHANGELOG.md`.
6. **Гейт G2 (YUV).** `bash tool/ci/scope_guard.sh <base>` вернёт `scope: all` (затронуты `example/integration_test/*`,
   `.github/workflows/ci.yml`, `tool/ci/*`): все доступные локальные проверки по AGENTS.md. Дополнительно:
   `rg -n -i 'camera|mlkit|google_mlkit' example/{lib,test,integration_test,pubspec.yaml}` — пусто (кроме комментариев
   про «синтетический поток»), сборка примера под Android/iOS/macOS/Windows/Web проходит без камерных плагинов.
7. **Пара и кандидаты — этап 2** (раздел 6).

Вложенность гейтов важна: удаление из YUV до G1 запрещено (Constraints PREP 1: покрытие не заменяется уменьшением матрицы).

## 6. Версии, место и регистрация

### Расположение и правила

Предлагается отдельный checkout `D:\.projects\yuv_camera` (каталога нет, подтверждено). Правила: свои `AGENTS.md`
(коротко: границы, `Probe` для путей, локальные проверки, CI по тегам по D-23), `todo.md`, `.memory/` (по
`D:\.projects\AGENTS.md` ближайшая память вверх от папки проекта; у `yuv_camera` её нет — создаётся своя; записи из
`.memory/MEMORY.md` `yuv_ffi`, относящиеся к камере, переносятся туда на этапе 1, пути в них обновляются), `dev`/`main`
как в YUV. Протокол ролей общий (`D:\.projects\ENGINEERING_PROTOCOL.md`). Пробы (`windows`, `pixel3`, `web`) определяются
в `AGENTS.md` `yuv_camera` по таблице путей: камерный Dart-код — `windows+web`, устройства — device-check вручную.
Remote, имя репозитория, лицензия, `repository`/`homepage`/`issue_tracker`, `publish_to` — Engineer (раздел 7). Соседний
проект в этой задаче не создан.

### Связь версий

`yuv_camera 0.0.1` → `yuv_ffi: ^0.5.2`; `yuv_ffi 0.5.2` не меняет публичный API (камера лишь уходит). Порядок выпуска
(`todo.md`, этап 3): `yuv_ffi 0.5.2`, затем `yuv_camera 0.0.1`. До публикации 0.5.2 `^0.5.2` не разрешается с pub.dev:
`flutter pub get` в `yuv_camera` требует локальной подмены. Подмена — `pubspec_overrides.yaml` (в `.gitignore`
`yuv_camera`, чтобы не попасть ни в коммиты, ни в публикацию). В публикуемом `pubspec.yaml` `path`-зависимости нет.

Следствие для CI. Workflows `yuv_camera` до публикации YUV 0.5.2 могут запускаться только если раннер получает
кандидата YUV (второй checkout по SHA + генерация override). Это настройка этапа 2 и зависит от remote (раздел 7, Q1);
на этапе 1 работают локальные проверки.

### Потребитель пары

- Этапы 1–2: `yuv_camera/example` — потребитель с обеими зависимостями (`yuv_ffi`, `yuv_camera`) и всеми перенесёнными
  проверками; основной `yuv_ffi/example` камерой не нагружается.
- Этап 3 (финал): временный независимый потребитель вне обоих репозиториев (`flutter create` в рабочем каталоге) с
  опубликованными `yuv_ffi: 0.5.2` и `yuv_camera: 0.0.1` + `camera_desktop`: `pub get`, `analyze`, сборка Windows и Web,
  один прогон `camera_capture_native_test`-аналога. Скрипт создания — в `yuv_camera/tool/` и коммитится как скрипт, не как
  проект.

### Регистрация desktop-провайдера: A1 подтверждается

Факты (по чтению):

- `camera_desktop 2.0.0` в своём `pubspec.yaml` объявляет `flutter.plugin.implements: camera` и для `linux`, `macos`,
  `windows` — `dartPluginClass: CameraDesktopPlugin`. Регистрацию генерирует инструмент Flutter для приложения, у которого
  плагин есть в зависимостях; README плагина: «Add `camera_desktop` alongside `camera` in your `pubspec.yaml`».
- В `example/` нет ни одного `package:camera_desktop/…`; плагин присутствует только в `pubspec.yaml` и в tracked
  registrants (`windows/flutter/generated_plugin_registrant.cc`, `macos/Flutter/GeneratedPluginRegistrant.swift`).
  Значит регистрация сегодня целиком выполняется инструментом по зависимости приложения.
- Io-источник использует только `CameraPlatform.instance` из `camera_platform_interface` и `CameraController` из
  `camera`; символов `camera_desktop` в камерном коде нет.

Вывод. A1: приложение (`yuv_camera/example`, любой потребитель) объявляет `camera_desktop: ^2.0.0`; пакет `yuv_camera`
`camera_desktop` не зависит и не регистрирует. Препятствий для A1 не найдено, A2 не нужен; адаптаций кода не требуется.
Проверка в карточке: сгенерированные registrants примера камеры содержат `camera_desktop`, затем цели 5–6. README
`yuv_camera` обязан сказать потребителю: на desktop добавить `camera_desktop`; на macOS — `NSCameraUsageDescription` и
entitlement `device.camera`; на Linux — GStreamer (`libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev`); Android/iOS —
разрешения плагинов `camera`.

## 7. Остаточные решения Engineer и наблюдения

| № | Вопрос | Рекомендация | Что блокирует |
| --- | --- | --- | --- |
| Q1 | Remote и публикационные данные `yuv_camera` (имя репозитория, лицензия, URL в `pubspec`), доступ CI `yuv_camera` к кандидату `yuv_ffi` до публикации | создать после этапа 1; до тех пор только локальные проверки | первый CI-запуск `yuv_camera`; этап 2 |
| Q2 | Нужна ли отдельная YUV-проба физического показа шейдера в release (device-check уходит из YUV, 3.1) | не вводить: подтверждать в релизном гейте через device-check пары | гейт этапа 2 |
| Q3 | Подтвердить, что действующий источник по iOS-ориентации — APPLE 1 (проверено на одном iPhone), а формулировка «не проверено» в dartdoc устарела (3.7) | да; текст `yuv_camera` — по границе APPLE 1 | тексты README/dartdoc `yuv_camera` |
| Q4 | Подтвердить расположение `D:\.projects\yuv_camera` и собственную память | да | этап 1, первая карточка |

Решения Architect при нарезке (не Engineer): раскладка тестов «путь в путь» (3.4); сделать ли `ios_bgra_camera_frame_test`
и C5 `*_native_test` (расширение CI); судьба пина iOS 18.x и платформы 15.5 в YUV (2.5); имя ручной цели
`camera_flow_test`.

Предлагаемая нарезка этапа 1 (имена условные; порядок = зависимости):

1. Каркас и API `yuv_camera` (раздел 5, шаги 1–2, `lib/`).
2. Пример камеры: раннеры, экраны, device-check, ML Kit, экран результата (2.1, 2.5).
3. Тесты и скрипты `yuv_camera`, гейт G1 (2.2, 2.3, 4, 5.3–5.4).
4. Упрощение `yuv_ffi/example` + редактор + `crop`-кейс (5.5, зависит от 3).
5. CI, README, `doc/`, версия 0.5.2 `yuv_ffi` (2.6; зависит от 4).
6. Локальная проверка пары (раздел 6; зависит от 3 и 5).

Наблюдения вне объёма переноса (не исправлялись):

- `example/test` не запускается ни одним скриптом CI (2.2).
- `YuvCameraFrame` dartdoc устарел относительно APPLE 1 (3.7); `library: 'yuv_ffi example'` в `FlutterErrorDetails` (2.1).
- `test/pack_planes_native_equivalence_test.dart`: ссылка на несуществующий тест (2.6).
- `example/pubspec.yaml`: `ffi` без потребителя, комментарий про «Camera frame benchmarks» (1); iOS `PERMISSION_CAMERA=1`
  без `permission_handler` (2.5).
- Записи `.memory/MEMORY.md` yuv_ffi с путями `example/lib/camera/camera_image_import.dart` и `example/lib/ext.dart`
  устареют после переноса — править в карточке переноса (`Memory: ~`).

## 8. Рассмотренные пути

`example/lib/**` (21 файл, прочитаны все), `example/test/**` (13 файлов, прочитаны все), `example/integration_test/`
(5 камерных и смешанных целей прочитаны; остальные проверены `rg` на `camera|mlkit|face|editor|device_check|fake_camera`
и на импорты `yuv_ffi_example`), `example/integration_test/helpers/**` (поиск `rg`), `example/probe/**`,
`example/test_driver/**`, `example/tool/**`, `example/assets/**` (список), `example/pubspec.yaml`, `example/pubspec.lock`
(версии камерных пакетов), `example/analysis_options.yaml`, `example/README.md`, `example/web/index.html`,
`example/android/app/{build.gradle,src/main/AndroidManifest.xml}`, `example/ios/{Podfile,Podfile.lock,Runner/Info.plist}`,
`example/macos/{Podfile,Runner/Info.plist,Runner/*.entitlements,Flutter/GeneratedPluginRegistrant.swift}`,
`example/windows/flutter/generated_*`, `tool/ci/*` (прочитаны `windows.ps1`, `example.ps1`, `vm.ps1`, `smoke.ps1`,
`android.ps1`, `scope_guard.sh`, `ios.sh`, фрагменты `macos.sh`, `web.ps1`, `web.sh`, `drive.*`), `tool/probe/*.ps1`
(`rg`), `.github/workflows/*` (все), корневые `pubspec.yaml`, `README.md`, `CHANGELOG.md`, `AGENTS.md`, `COMPLETION.md`,
`doc/*`, `test/pack_planes_native_equivalence_test.dart`, `test/probe/*` (`rg`), `lib/` (`rg` по `camera|ML Kit`),
`D:\.projects\MACHINES.md` (`rg`), pub cache: `camera_desktop-2.0.0/pubspec.yaml` и `README.md`, `camera-0.11.0+2/pubspec.yaml`,
`camera_android_camerax-0.6.10+3` (манифест); история: `git show 02a0796` (APPLE 1), `git log` по удалённым тестам.
