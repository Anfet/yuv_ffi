# yuv_ffi — принятые задачи аудита 0.4.1

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

# SPEED-00 — Подготовлен отдельный Dart FFI тест

- Исполнитель: GPT-5.6 Terra (T2). Добавлен чистый Dart package `speed_00_dart_ffi`; тест загружает текущую Windows Release DLL напрямую через `dart:ffi`, без Flutter API и существующего bench suite.
- `dart test test/yuv_flip_v1_test.dart -r expanded`: I420 1280×720, 20 warm-up и 200 вызовов; среднее 46,513.47 мкс/вызов; FNV-1a checksum `0xef3bff85fcdefd25`; все status и каждый output sample прошли проверки.
- Независимый повтор: 46,162.96 мкс/вызов, тот же checksum; `dart format --output=none --set-exit-if-changed test/yuv_flip_v1_test.dart` — 0 изменений. Formatter сообщил, что корневой `flutter_lints` недоступен из отдельного Dart package; это не помешало форматированию или тесту.
- Принято после независимой проверки. Коммит содержит реализацию, тест и этот completion record.
