# yuv_ffi — история проверок и принятых задач

## OPT-14 — REVIEW — Проверить Dart row-copy fast paths

- Изолированный Windows Dart эксперимент на padded BGRA 1920×1080 подтвердил гипотезу: ROI seed 49.403 → 27.190 ms, copy-back 45.194 → 11.844 ms. Кандидат применим только при плотном pixel stride и сохраняет row padding; pixel gaps остаются на прежнем sample-wise пути.
- Контрактные тесты кандидата прошли для padded rows, pixel gaps и ROI seed; native library на этом хосте отсутствовала, поэтому native-dependent проверки были skipped. Production Dart/C/ABI не менялись. Детали: [OPT-14 report](doc/perf/results/opt14_windows_row_copy.md).

## BLUR-04 — DONE — Измерить разделимый Gaussian по Y/U/V

- На Pixel 3 Release/AOT два независимых прогона разделимого Y/U/V Gaussian дали 186.225 ms для 1477×1065 и 28.783 ms для 720×360; прямой 2D Y/U/V — 937.816/147.547 ms. Ускорение 5.04×/5.13× при том же публичном вызове.
- На этих входах выходные checksum разделимого и прямого 2D YUV совпали; raw NV12 большого кадра побайтно совпал (max delta 0, различий 0). Scratch: 242.3 KiB при 1477×1065/r10; оценка 15.66 MiB при 4000×3000/r256. Кандидат и область применимости описаны в [отчёте](doc/perf/results/blur04_pixel3_gaussian_separable.md); production C/ABI не менялись.

## BLUR-03 — DONE — Измерить Gaussian напрямую по Y и Y/U/V

- Изолированный 2D кандидат на Pixel 3, Android Release/AOT: для 1477×1065 RGB 1427.865 ms, Y-only 829.745 ms, Y/U/V 938.257 ms; для 720×360 225.534, 129.841 и 147.677 ms. Полный Y/U/V экономит 34.29%/34.52% при сохранённой 2D сложности. Повторный Y/U/V прогон дал близкие медианы 937.358/148.361 ms и те же checksum.
- Два candidate patch, raw JSONL/logcat, source SHA и три фактических PNG сохранены в [отчёте](doc/perf/results/blur03_pixel3_gaussian_direct_yuv.md). Проверка принята как эксперимент; production C/ABI не менялись, production-перенос не принят. Визуальная семантика YUV отличается от RGB.

## BLUR-02 — Измерить Mean напрямую по Y и Y/U/V

- Принято как изолированный эксперимент: отдельный `yuv_mean_blur_v1.c` кандидат измерен на Pixel 3 без изменения production ABI/C. Контрольный Y/U/V повтор после idle дал на 720×360 RGB 8.644 ms, Y-only 1.648 ms, Y/U/V 2.538 ms; на 1477×1065: 54.374, 12.695 и 18.005 ms. Исходный шумный Y/U/V прогон сохранён в raw и не репрезентативен; source/diff и checksum исключили отдельный kernel или dispatch. Межсессионная вариативность не позволяет принять production threshold; production-перенос не принят.
- Исходный source diff подтверждает, что текущие Box/Mean эквивалентны по kernel; candidate output SHA побайтно совпал с BLUR-01 для соответствующих Y-only/YUV вариантов, поэтому три проверенных PNG BLUR-01 переиспользованы. Raw и детали: `doc/perf/results/blur02_pixel3_mean_direct_yuv.md`.

## BLUR-00 — Подготовить Pixel 3 Release runner и baseline

- Принято 2026-09-26. Добавлен отдельный Dart runner и PowerShell-скрипт, которые запускают одну выбранную публичную blur-операцию в Release и сохраняют raw logcat/JSONL; Pixel 3 проверен для всех трёх операций и двух размеров. PNG decode, packed `Y + UV` подготовка и source clone не входят в таймер.
- 720×360 медианы: Box 8.562 ms, Mean 8.644 ms, Gaussian 225.356 ms. Для 1477×1065: 54.943 ms, 54.374 ms и 1427.216 ms. Box/Mean output SHA совпадает ожидаемо: обе native функции реализуют один uniform kernel. `flutter analyze lib/main.dart` прошёл; подробные raw samples и ограничения формата записаны в `doc/perf/results/blur_reference_pixel3_blur00.md`.

## BLUR-01 — Измерить Box напрямую по Y и Y/U/V

- Принято 2026-09-26 как изолированный эксперимент; production ABI/C не менялись. На Pixel 3 полный публичный вызов для tight packed NV12 дал на 720×360: RGB 8.562 ms, Y-only 1.676 ms (−80.42%), Y/U/V 2.548 ms (−70.24%); на 1477×1065: 54.943, 12.738 (−76.82%) и 17.967 ms (−67.30%). Визуально RGB и Y/U/V неразличимы на эталонном кадре; Y-only меняет видимое поведение, сохраняя исходную chroma. Декодируемые PNG, raw timings, checksums и ограничения tight/full-frame кандидата записаны в `doc/perf/results/blur01_pixel3_box_direct_yuv.md`.

## История release candidate 0.4.1

Кандидат 0.4.1 отменён до публикации и создания тега; следующая целевая версия — 0.4.2. Результаты ниже сохраняют фактическую версию и SHA на момент проверки и не являются приёмкой 0.4.2.

## AUD-06 — Подготовить metadata и принять релизный кандидат

- Принято release owner на SHA `d4cb31e` после закрытия AUD-13/14/17.
- Версия `0.4.1` согласована в package metadata; чистый `flutter pub publish --dry-run` дал 0 warnings и ожидаемый hint о скачке от последней non-retracted версии `0.2.4`. Архив включал WASM JS/WASM и исключал `todo.md`, `todo-waitlist.md`, `COMPLETION.md`.
- CI run `36114993161` имел общий success: 11/12 jobs прошли; `android-armv7-runtime` был non-blocking и нестабилен на GitHub-hosted emulator. Physical-device proof принят по AUD-17.
- Публикация и Git tag не выполнялись. Повторные замечания новой предпроверки и gate на новом SHA ведутся в AUD-18—21.

## AUD-13 — Проверять публикуемый WASM-артефакт в CI

- Принято независимым review (Opus), 2026-09-25. Emscripten build использует стабильный список tracked C sources; CI нормализует mode перед byte-for-byte сравнением.
- На run `36101900152` rebuild comparison и Web integration/reference gates прошли. На текущем принятом baseline run `36117003942` job `wasm-web-integration` также прошёл.
- WASM assets присутствуют в dry-run archive. Результат подтверждает соответствие assets C sources и CI gate; полный Web parity не заявляется.

## AUD-14 — Закрыть browser и платформенные сценарии

- Принято независимым review (Opus), 2026-09-25. Web atomicity assertions используют публичный `YuvPixelFormat`; необходимые анализаторы прошли на Flutter 3.38.10 и 3.44.9.
- CI run `36101986461` подтвердил browser fake-module contracts (41 tests) и Web reference matrix на одном SHA. Run `36117003942` на `35c516e` подтвердил green CI jobs для Web integration, обеих Flutter версий и example builds.
- Частичный Web backend остаётся явно задокументированным. Полный native suite на ARM64 вынесен в неблокирующую AUD-23; Android ARMv7 runtime закрыт физическим device evidence в AUD-17.

## AUD-17 — Подтвердить ARMv7 runtime

- Принято release owner, 2026-09-25, по физическому runtime evidence; исполнение на ARMv7 GitHub-hosted emulator не является надёжным gate.
- ARM-only APK с `libyuv_ffi.so` прошёл `flutter drive` smoke на Google Pixel 3 (`blueline`, ARM64 с нативной ARMv7 совместимостью): VM service подключился, `All tests passed`.
- GitHub-hosted x86_64 emulator job нестабилен (примерно 1 успех из 4 наблюдавшихся прогонов) и помечен non-blocking; общий CI run `36117003942` завершился success при ошибке этого job. ARMv7 остаётся поддерживаемой ABI.
- Известный предел: полный `flutter drive` через эмуляторный native bridge не подтверждён стабильно. Отдельная проверка полного native suite на ARM64 ведётся в AUD-23.

## AUD-01 — Нижняя граница SDK

- Принято: восстановлены исполняемые проверки legacy API и адресные подавления deprecated-диагностик; CI выполняет analyzer и VM-тесты на Flutter 3.38.10 и 3.44.9.
- Доказательство: GitHub Actions run 36043175625 на `ec2ea95` прошёл на обеих версиях. Ранее выполнены локальный analyzer и 41 тест `test/conversions_test.dart` с нативной библиотекой.

## AUD-02 — Первая iOS Simulator сборка

- Принято: обновлён `Podfile.lock`, подготовка Pods-Runner и simulator smoke выполняются до unsigned device build.
- Доказательство: чистый checkout прошёл `pod install`, сборку симулятора, `native_app_runtime_smoke_test.dart` и device build; GitHub Actions run 36015478340 прошёл весь iOS job.

## AUD-03 — Физический iPhone и BGRA layout

- Принято: полный camera/ML Kit flow и независимый BGRA pixel-эталон с padding прошли на сопряжённом iPhone.
- Доказательство: оба `flutter drive` завершились с кодом 0 и `All tests passed`; camera flow обнаружил лицо, выполнил crop и negate. Pixel-эталон проверил точные tight-BGRA байты после исходного `rowStride == 12`.

## AUD-04 — Документация и матрица проверок

- Принято: `README.md` и `doc/api-abi-0.4-design.md` описывают текущие CI цели, iOS smoke, частичный Web backend и реальные 119 reference cases без приписывания отдельному BGRA-тесту проверки геометрии.
- Доказательство: manifest, integration-тесты и workflow сверены с текстом; `git diff --check` прошёл. Изменения документационные.
- Коммит: изменения пока находятся в рабочем дереве.

## AUD-05 — Android app-runtime smoke

- Принято: локальный Android app-runtime smoke прошёл на API 35 x86_64 emulator и физическом arm64 устройстве; example использует NDK 28.2.13676358. Отдельная проверка CI шага завершена в AUD-09.
- Доказательство: оба локальных smoke загрузили библиотеку, выполнили конверсию и `applyNegate()`; [GitHub Actions run 36062365665](https://github.com/Anfet/yuv_ffi/actions/runs/36062365665) подтвердил Android job на `f8dfd61`.
- Коммит: изменения пока находятся в рабочем дереве.

## AUD-11 — Граница Flutter Web `--wasm`

- Принято: README различает частичный C/WASM backend и режим компиляции Flutter приложения. Поддержанная команда — обычный `flutter build web`; `flutter build web --wasm` пока явно объявлен неподдерживаемым из-за импорта `dart:html` в loader.
- Доказательство: diff `b928753cc777839aaaf9f0d868411da1c0243ead` согласован с `lib/src/loader/impl/wasm_loader_web.dart`; исполнитель собрал example в JS режиме на Flutter 3.44.9 и воспроизвёл ошибку dart2wasm.
- Коммит: `b928753cc777839aaaf9f0d868411da1c0243ead`.

## AUD-12 — Минимальные Android/iOS версии

- Принято: README указывает Android API 26 и iOS 13.0 и показывает `minSdk = 26` для Android приложения.
- Доказательство: diff `1ccb9df8f8a036cbdfb4ab962de524853d329fca` совпадает с `android/build.gradle` и `ios/yuv_ffi.podspec`; исполнитель собрал чистый временный Flutter consumer с minSdk 26.
- Коммит: `1ccb9df8f8a036cbdfb4ab962de524853d329fca`.

## AUD-15 — Точность публичных комментариев

- Принято: исправлены pixel координаты `Rect`, Safari SIMD минимум 16.4, комментарии о UV порядке и Android ABI; README перечисляет недостающие публичные exports.
- Доказательство: diff `10e2f09ab64b848fc29f6553f4389ceb83b18c74` сверён с `YuvImage` и YuvPlane контрактом; повторный `dart format --output=none --set-exit-if-changed` для затронутых Dart файлов прошёл. Оговорку README о ещё не запущенном Android CI шаге нужно обновить в AUD-06 после успешного run `36062365665`.
- Коммит: `10e2f09ab64b848fc29f6553f4389ceb83b18c74`.

## AUD-16 — Происхождение Windows DLL

- Принято: локальный Windows packaging smoke выполнен со свежей ignored `D:\.projects\yuv_ffi\yuv_ffi.dll`; tracked файлы задача не меняла.
- Доказательство: SHA256 DLL `9C816B9F59EE159573575C2916321693AE035161D99B92274D9FC21A22365F30` повторно проверен. `llvm-readobj --coff-exports` показывает ровно 11 `yuv_*_v1` экспортов без legacy символов; исполнитель сообщил об успешном `flutter test test/native_packaging_smoke_test.dart --no-pub`. Старый файл сохранён в `%TEMP%\yuv_ffi_aud16\yuv_ffi_stale_20260923.dll` (SHA256 `4E610B76BBD4181CD08EB0B9A51CC915B0EE7B2D6AC7D8BB3CB44BD36F7CE472`).
- Export manifest: `yuv_black_white_v1`, `yuv_box_blur_v1`, `yuv_chroma_swap_v1`, `yuv_convert_v1`, `yuv_crop_v1`, `yuv_flip_v1`, `yuv_gaussian_blur_v1`, `yuv_grayscale_v1`, `yuv_mean_blur_v1`, `yuv_negate_v1`, `yuv_rotate_v1`.
- Коммит: неприменим для локального ignored DLL.

## AUD-07 — Миграция blank copy с padding

- Принято: README и dartdoc различают tight `YuvImage.allocate` и blank copy с сохранением strides; новая regression выполняет рекомендованную миграцию через named factories для padded I420, NV12 и BGRA.
- Доказательство: commits `20b5059140d6e7aa09ce2c8d16468116b3425008`, `42c75b960304e177503466f4106c5310dbea9756`; тест проверяет формат, размеры, каждый `rowStride`/`pixelStride`, нулевые байты и независимость от исходного кадра. Независимый `flutter test test/yuv_image_state_contract_test.dart test/yuv_apply_surface_test.dart --no-pub` прошёл: 49 тестов.

## AUD-08 — Формат Android app-runtime smoke

- Принято: smoke-файл приведён к `dart format`; job `android-native-build` выполняет отдельный formatter gate из `example/`.
- Доказательство: commits `6f733eff50ecb4e727d548e921da86f6c8f8e873`, `5bd97d4b079e8c19b00abd2e90cbef5410f33dc0`; независимый `dart format --output=none --set-exit-if-changed` завершился кодом 0. Фактический GitHub Actions run завершён в AUD-09.
- Исправление после [CI run 36059202255](https://github.com/Anfet/yuv_ffi/actions/runs/36059202255): commit `955442b0791c4e8e034d532e3b1f34e1f0ab6fb7` перенёс gate после `Flutter pub get (example)`, чтобы `package:flutter_lints/flutter.yaml` разрешался при форматировании. Проверены порядок в workflow, `dart format` (0 изменений), `git diff --check`; [run 36062365665](https://github.com/Anfet/yuv_ffi/actions/runs/36062365665) подтвердил gate в CI.

## AUD-10 — Граница IO initialization

- Принято: README и dartdoc перечисляют capability-gated processing methods, выделяют `applyPlanes` как доступный до bootstrap Dart-only путь и сохраняют ясный `UnsupportedError` для gated вызовов.
- Доказательство: commits `1e2dafffac674b1964ca6cdcbc7b0deddc0a242c`, `d12eb2b278e397d51be596384a0cb9d565837421`; новый тест вызывает `applyPlanes` до `initialize()` и проверяет замену плоскостей. Независимый целевой прогон прошёл: 49 тестов в двух файлах, `dart format` изменений не предложил.

## AUD-09 — Android emulator CI smoke

- Принято: `android-native-build` вызывает `reactivecircus/android-emulator-runner@v2` с `working-directory: example`, однострочным `flutter drive` и подготовкой KVM. Порядок formatter gate исправлен ранее в AUD-08.
- Доказательство: [GitHub Actions run 36062365665](https://github.com/Anfet/yuv_ffi/actions/runs/36062365665) на `f8dfd61a0d4d75a4b5651599a71f39d8207607d5`: job `android-native-build` прошёл; лог показывает `Formatted 1 file (0 changed)`, ABI `x86_64` и `All tests passed` для app-runtime smoke. Рабочий Android путь после этого run не менялся. Полный CI на итоговом SHA остаётся выпускным gate в AUD-06.
- Коммиты: `14b958e8afb54271a95b0d2692c12ef43ace5b51`, `955442b0791c4e8e034d532e3b1f34e1f0ab6fb7`.
# AUD-18 — Актуализирован Android CI в README

- Принято после независимой сверки README с CI workflow и run 36117003942; diff ограничен Android CI формулировкой, Android x86_64 smoke отделён от ARMv7 evidence.
- Проверка: `git diff --check -- README.md` прошла.

# AUD-19 — Синхронизирован tracked lockfile примера

- На момент приёмки `example/pubspec.lock` фиксировал `yuv_ffi 0.4.1` и resolver Flutter 3.44.9; изменены пять транзитивных версий. Flutter 3.38.10 сохранял прежние разрешения этих зависимостей, оставлен один воспроизводимый lockfile. При переходе на 0.4.2 запись path-зависимости обновлена отдельно.
- Проверки на Flutter 3.38.10 и 3.44.9: `flutter analyze` и `flutter build web --release` прошли; повторный `flutter pub get` на 3.44.9 не меняет lockfile. Web build выводит ожидаемые WASM dry-run предупреждения о `dart:html`. `pubspec.yaml` и constraints не менялись.

# AUD-20 — Уточнены release notes кандидата 0.4.1

- Принято: верхняя запись CHANGELOG перечисляет подтверждённые изменения и ограничения, не предполагает причину retraction 0.4.0 и сохраняет статус Web как partial WASM backend.
- Проверка: `git diff --check`; `CHANGELOG.md` и `pubspec.yaml` остаются на версии 0.4.1.

# AUD-22 — Проверен Web/WASM runtime на Flutter 3.38.10

- Принято: asset-backed `flutter drive` прошёл в браузере на Flutter 3.38.10 / Dart 3.10.9 в чистом detached checkout `35c516e`; Chrome и ChromeDriver 152.0.7977.82. `wasm_bootstrap_test.dart` реально выполняет `YuvFfi.initialize()` и RGBA→BGRA→I420→BGRA; ChromeDriver сообщил `result: true`, без failure details.
- Shared checkout не затронут; backend/API/CI не менялись. `git diff --check -- todo.md` прошёл.

# AUD-23 — Зафиксировано ограничение ARM64 native suite

- Принято как неблокирующая проверка с явным инфраструктурным ограничением: полного ARM64 Linux suite выполнить не удалось, так как доступная машина — Windows x64 без ARM64 Linux runner, CMake/CTest, QEMU или Docker/Podman. Android NDK не подменяет Linux ABI/sanitizer gate.
- Записано 0/11 CTest targets, сохранённые sanitizer требования и воспроизводимая команда для ARM64 Linux host/QEMU. C/C/CMake и sanitizer gate не менялись.

# AUD-24 — Проверен чистый Windows consumer

- Принято: consumer вне репозитория использовал path dependency на чистую package-копию из `git archive` SHA `35c516e`; до сборки в ней отсутствовал DLL. `flutter build windows` успешно собрал приложение; DLL штатно собрана CMake из package source и bundled Flutter plugin path, ручное копирование не выполнялось.
- `flutter drive` завершился `All tests passed` в consumer process и проверил initialize, conversion и negate. Исходная DLL из корня checkout не использовалась; код плагина/native C не менялся.

# AUD-25 — Обновлён Android Gradle toolchain

- Принято: Android wrapper обновлён до Gradle 8.14.3, AGP до 8.11.1, Kotlin Gradle Plugin до 2.2.20 — пороговых версий, о которых предупреждал Flutter.
- `flutter build apk --debug` завершился успешно на Flutter 3.38.10 и 3.44.9 без Flutter dependency-validation warnings. Остались не связанные с toolchain javac deprecation/unchecked warnings от `camera_android_camerax` и ML Kit зависимостей.
- Для проверки 3.38.10 временно выполнен `flutter pub get`, затем lockfile восстановлен resolver-ом 3.44.9; итоговый tracked `example/pubspec.lock` сохраняет AUD-19 разрешение. Изменений Android поведения, SDK/NDK или версии пакета нет.

# MEAS-01 — Подготовлен Windows benchmark

- Принято после независимого ревью и исправлений: добавлены публичный Dart AOT runner, сборка/драйвер, watchdog, fallback CSV для не записавших строку процессов, манифесты сборки и packed active-sample checksum.
- Windows release smoke подтвердил 0.2.4 и ABI v1 для 1080p и 12 MP; ошибка строки сохраняет `ERROR:setup` и не останавливает следующие сценарии. `CVT.NV12.I420` checksum совпал с C-стендом для обеих версий. Детали и локальные CSV пути — `doc/perf/MEAS-01-run-instructions.md`.
- Проверки: `dart analyze tool/bench/dart`, форматирование, PowerShell parse и `git diff --check` прошли. MEAS-02/03 и пооперационные baseline к этой приёмке не относились.

# SPEED-00 — Подготовлен отдельный Dart FFI тест

- Исполнитель: GPT-5.6 Terra (T2). Добавлен чистый Dart package `speed_00_dart_ffi`; тест загружает текущую Windows Release DLL напрямую через `dart:ffi`, без Flutter API и существующего bench suite.
- `dart test test/yuv_flip_v1_test.dart -r expanded`: I420 1280×720, 20 warm-up и 200 вызовов; среднее 46,513.47 мкс/вызов; FNV-1a checksum `0xef3bff85fcdefd25`; все status и каждый output sample прошли проверки.
- Независимый повтор: 46,162.96 мкс/вызов, тот же checksum; `dart format --output=none --set-exit-if-changed test/yuv_flip_v1_test.dart` — 0 изменений. Formatter сообщил, что корневой `flutter_lints` недоступен из отдельного Dart package; это не помешало форматированию или тесту.
- Принято после независимой проверки. Коммит содержит реализацию, тест и этот completion record.

# C-01 — Ускорен `yuv_flip_v1`

- Исполнитель: GPT-5.6 Terra (T2). По C-коду тега `0.2.4` подтверждён быстрый прямой обход плоскостей: горизонтальное обращение samples, вертикальная перестановка строк. В ABI v1 добавлен плотный путь на `yuv_flip_v1.c`: горизонтально копируются samples в обратном порядке, вертикально строки через `memcpy`; odd 4:2:0 и stride/pixel gaps остаются на phase-correct общем ядре.
- Адресный Dart FFI тест расширен до I420/NV12/BGRA × H/V, проверяет каждый output sample и checksum, таймер охватывает только вызовы функции. Windows Release до → после, мкс/вызов: I420 H 46,575 → 2,702 (17.24×), V 47,616 → 111.84 (425.9×); NV12 H 39,782 → 2,365 (16.82×), V 39,981 → 127.62 (313.3×); BGRA H 32,613 → 2,693 (12.11×), V 31,838 → 341.05 (93.4×). Все шесть oracle/checksum прошли; независимый повтор `dart test test/yuv_flip_v1_test.dart -r expanded` прошёл.
- Принято после просмотра native diff и повторного теста. Изменены `src/yuv/abi/yuv_flip_v1.c`, `speed_00_dart_ffi/test/yuv_flip_v1_test.dart`, инструкция теста. Коммит: `cd09d99`.

# C-02 — Ускорен `yuv_convert_v1`

- Исполнитель: GPT-6 Sol (T1). В C `0.2.4` найдены прямые проходы по строкам/плоскостям. ABI v1 получил прямое копирование плотных строк, plane-aware copy/relayout, fused packed→YUV luma+chroma pass на блок 2×2 и специализированный YUV/RGBA→BGRA путь; ABI и общий helper не менялись.
- Адресный Dart FFI тест проверяет все 12 разрешённых пар при 1281×721, каждый output byte против независимого oracle, статус и checksum. Windows Release, мкс/вызов до → после (speedup): I420→I420 48406.38→117.91 (410.54×); I420→NV12 40267.91→747.59 (53.86×); I420→BGRA 69611.80→5683.71 (12.25×); NV12→I420 39383.95→838.99 (46.94×); NV12→NV12 41334.64→111.27 (371.48×); NV12→BGRA 56132.21→5867.72 (9.57×); BGRA→I420 67704.86→3813.29 (17.75×); BGRA→NV12 64982.21→3651.93 (17.79×); BGRA→BGRA 32144.15→327.42 (98.17×); RGBA→I420 68228.20→4053.50 (16.83×); RGBA→NV12 64912.59→3642.38 (17.82×); RGBA→BGRA 36818.60→1529.78 (24.07×). Same-format and I420↔NV12 остаются byte-exact. NV12→BGRA — 9.57× после проверенной альтернативы; bottleneck — полный BT.601 decode/clamp на каждый pixel.
- Принято: независимый `dart test test/yuv_convert_v1_test.dart -r expanded` — 12/12; format/analyze без замечаний; `abi_convert_tests`, `abi_status_tests`, `abi_sanitizer_tests` — 3/3; `git diff --check` чисто. Коммит: `869efb3`.

# C-03 — Ускорен `yuv_crop_v1`

- Исполнитель: GPT-5.6 Terra (T2). Legacy crop `0.2.4` использует построчный memcpy, но floor chroma и прямой UV-copy ломают odd-origin/odd-edge правила ABI v1. Добавлен tight-packed fast path: Y/BGRA row-copy, aligned 4:2:0 chroma row-copy, иначе прямой Y-copy и phase-correct chroma recompute. Fast path требует tight source/destination pixel и row strides; padded layout безопасно идёт через generic kernel.
- Один адресный Windows Dart FFI тест проверяет I420/NV12/BGRA aligned, odd-origin/odd-edge случаи и I420 odd-origin с padded source rows; каждый output sample и checksum oracle проверяются вне batch timer. До → после, мс/вызов (speedup): I420 aligned 25.51707→0.03477 (733.8×), odd origin 51.46728→4.58196 (11.23×), odd edge 51.42297→4.98110 (10.32×); NV12 aligned 21.67528→0.03173 (683.1×), odd origin 44.13614→4.74567 (9.30×), odd edge 43.64942→4.75129 (9.19×); BGRA even 17.24063→0.19989 (86.25×), odd 17.22686→0.19167 (89.87×). NV12 phase cases retain ~9× cost from required chroma decode/average/encode.
- Принято после native diff review и независимого финального `dart test test/yuv_crop_v1_test.dart -r expanded`: 9/9, все checksum совпали. `dart format` без изменений, `dart analyze` без замечаний, `git diff --check` чисто. Коммит: task-specific commit is recorded in Git history.

# C-04 — Ускорен `yuv_rotate_v1`

- Исполнитель: GPT-5.6 Terra (T2). Legacy `0.2.4` проходит по output pixels и копирует stored samples напрямую; ABI v1 получил tight-packed direct plane path, а odd 4:2:0/padded/gapped input остаётся на phase-aware generic kernel.
- Адресный Dart FFI test покрывает I420/NV12/BGRA × 90/180/270, выходную геометрию, все samples и checksum вне batch timer. Windows Release, мс/вызов до → после (speedup): I420 90 45.512→4.107 (11.08×), 180 45.071→4.502 (10.01×), 270 45.364→4.535 (10.01×); NV12 90 38.828→3.425 (11.34×), 180 38.602→3.733 (10.34×), 270 38.709→3.784 (10.23×); BGRA 90 32.503→2.928 (11.10×), 180 30.384→2.999 (10.13×), 270 32.852→3.214 (10.22×).
- Принято после native diff review и независимого `dart test test/yuv_rotate_v1_test.dart -r expanded`: 9/9, oracle/checksums прошли; `dart format` без изменений, `dart analyze` без замечаний, `git diff --check` чисто. Task commit записан в Git history.

# C-05 — Ускорен `yuv_grayscale_v1`

- Исполнитель: GPT-5.6 Terra (T2). В `0.2.4` YUV grayscale нейтрализует chroma напрямую, что не сохраняет ABI v1 ROI boundary semantics. Добавлен локальный tight-packed path: BGRA grayscale с alpha preservation; I420/NV12 full-frame обрабатывает 2×2 блок одним decode и re-encode; ROI копирует untouched data, обрабатывает выбранные pixels и пересчитывает пересечённые chroma blocks. Padded/gapped/alias layouts остаются в generic kernel; shared helpers не менялись.
- Dart FFI test проверяет I420/NV12/BGRA × full-frame/ROI, bytewise BT.601 oracle и checksum вне batch timer; отдельный padded I420 ROI кейс проверяет fallback. Windows Release, мкс/вызов до → после (speedup): I420 full 176149.30→12143.55 (14.51×), ROI 141551.95→10893.50 (12.99×); NV12 full 153269.95→11915.05 (12.86×), ROI 121020.10→11176.05 (10.83×); BGRA full 60527.00→2462.15 (24.58×), ROI 47218.75→1745.80 (27.05×).
- Принято после native diff review и независимого `dart test test/yuv_grayscale_v1_test.dart -r expanded`: 7/7, oracle/checksums прошли; `dart format` без изменений, `dart analyze` без замечаний, `git diff --check` чисто. Task commit записан в Git history.

# C-06 — Ускорен `yuv_black_white_v1`

- Исполнитель: GPT-5.6 Terra (T2). `0.2.4` black-white для YUV thresholded stored Y/neutralized chroma, а BGRA used different strict floating threshold; neither preserves ABI v1 visible-RGB inclusive `gray >= 128` plus ROI-boundary chroma semantics. Added local tight-packed direct path; alpha is preserved, padded/gapped/alias cases stay on generic effect path.
- Dart FFI test checks I420/NV12/BGRA × full/ROI, visible gray 127/128/129, every output byte, checksum and padded I420 ROI fallback. Batch Windows Release mкс/вызов до → после (speedup): I420 full 178387.40→12302.80 (14.50×), ROI 142719.10→11180.20 (12.77×); NV12 full 155966.95→11965.70 (13.03×), ROI 122213.80→11334.85 (10.78×); BGRA full 61704.20→2321.85 (26.57×), ROI 47816.20→1617.75 (29.56×).
- Принято после исправления comments, native diff review и независимого `dart test test/yuv_black_white_v1_test.dart -r expanded`: 7/7, oracle/checksums прошли; format/analyze без замечаний, `git diff --check` чисто. Task commit записан в Git history.
