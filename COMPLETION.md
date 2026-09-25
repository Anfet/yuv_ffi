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
- Dart FFI test checks I420/NV12/BGRA × full/ROI, visible gray 127/128/129, every output byte, checksum and padded I420 ROI fallback. Batch Windows Release мкс/вызов до → после (speedup): I420 full 178387.40→12302.80 (14.50×), ROI 142719.10→11180.20 (12.77×); NV12 full 155966.95→11965.70 (13.03×), ROI 122213.80→11334.85 (10.78×); BGRA full 61704.20→2321.85 (26.57×), ROI 47816.20→1617.75 (29.56×).
- Принято после исправления comments, native diff review и независимого `dart test test/yuv_black_white_v1_test.dart -r expanded`: 7/7, oracle/checksums прошли; format/analyze без замечаний, `git diff --check` чисто. Task commit записан в Git history.

# C-07 — Ускорен `yuv_negate_v1`

- Исполнитель: GPT-5.6 Terra (T2). Legacy `0.2.4` изучен как алгоритмический ориентир; в ABI v1 добавлены локальные tight-packed fast paths: BGRA напрямую по пикселям, I420/NV12 с обработкой 2×2 блоков и корректным пересчётом shared chroma на ROI границе. Padded/gapped/alias layouts используют исходный generic kernel; ABI и общие helpers не менялись.
- Адресный Windows Dart FFI тест проверяет I420/NV12/BGRA × full-frame/ROI, все output samples, независимый oracle/checksum и padded I420 ROI fallback. Batch Release мкс/вызов до → после (speedup): I420 full 170351.30→10379.25 (16.41×), ROI 138941.85→10651.50 (13.04×); NV12 full 146396.35→10568.95 (13.85×), ROI 117968.45→10861.80 (10.86×); BGRA full 56864.25→1103.05 (51.55×), ROI 45116.15→912.00 (49.47×).
- Принято после просмотра native diff и независимого финального `dart test test/yuv_negate_v1_test.dart -r expanded`: 7/7; checksums совпали с отчётом, format/analyze и `git diff --check` прошли. Task commit записан в Git history.

# C-08 — Ускорен `yuv_chroma_swap_v1`

- Исполнитель: GPT-6 Luna (T3), независимая проверка — GPT-5.6 Terra (T2). В теге `0.2.4` отдельного swap нет; `nv21_to_nv12.c` меняет местами interleaved chroma samples при конверсии. ABI v1 получил tight NV12 path: непрерывное копирование Y и один проход по UV парам; padded/gapped layout остаётся на generic accessor fallback. ROI по контракту отвергается без записи в destination.
- Один Windows Dart FFI тест проверяет 1280×720 tight и padded/gapped NV12 каждый output byte/checksum/padding, плюс ROI rejection/no writes. Измерения независимо повторены на базовом коммите и итоговой DLL тем же тестом (100 вызовов в batch): tight baseline 3,521,130 мкс total / 100 = 35,211.30 мкс/call; после 20,319 мкс total / 100 = 203.19 мкс/call (173.3×). Padded/gapped baseline 3,566,111 / 100 = 35,661.11 мкс/call; после 3,534,031 / 100 = 35,340.31 мкс/call (1.01×, в пределах шума). Baseline DLL SHA-256 `AAE97B5C9134DE853216E8431664793C74535E6637F7A0E9AF939E53E4010B28`; итоговая DLL `50556BE0E304D9DD13CAC4AE1AB6DDF3A8C225A3187791ECA438E5AF47357A24`.
- Принято после просмотра C diff и независимого baseline rebuild из коммита перед C-08, Dart baseline/post прогонов, `dart analyze`, format и `git diff --check`. Все cases прошли с теми же checksums; временная DLL сборка legacy не выполнялась. Task commit записан в Git history.

# C-09 — Ускорен `yuv_box_blur_v1`

- Исполнитель: GPT-6 Sol (T1). По legacy `0.2.4` использован separable sliding-window приём; legacy округление между проходами, in-place запись и отдельная NV chroma семантика не переносились. Финальная ABI v1 реализация локальна в `yuv_box_blur_v1.c`: кольцо горизонтальных сумм на `min(height, 2*radius+1)` строк, вертикальные суммы и две выходные RGB строки; точный integer accumulation без промежуточного округления, edge replication и half-up деление на полную площадь. ROI читает полное окно source и пересчитывает только затронутую chroma, сохраняя odd-boundary поведение. Первоначальный full-frame scratch (192 MB на 12 MP) был отвергнут на review как мобильный memory риск и заменён bounded-ring вариантом до приёмки.
- Scratch равен `width * (12 * min(height, 2r+1) + 24)` байт с проверенными размерами и всеми allocations до первой записи. Для 4000×3000/radius 256: 24,720,000 bytes (~23.6 MiB), вместо 192 MB.
- Один Dart FFI test проверяет 12 сочетаний I420/NV12/BGRA × radius 1/3 × full/odd ROI, все output bytes и checksum; дополнительные cases: radius 0, odd/short frames с radius до 256, padded row/pixel strides и validation/no-write failures. Геометрия замеров 321×241, 3 warmup + 8 timed calls. До → после мкс/вызов (speedup): I420 r1 full 11544→2771 (4.17×), ROI 11978→3112 (3.85×), r3 full 28515→2927 (9.74×), ROI 23466→3168 (7.41×); NV12 r1 full 11329→2615 (4.33×), ROI 10306→3170 (3.25×), r3 full 26545→2636 (10.07×), ROI 22111→2896 (7.64×); BGRA r1 full 5329→1543 (3.45×), ROI 5197→1687 (3.08×), r3 full 13044→1553 (8.40×), ROI 9986→1712 (5.83×). Radius 1 remains below 10× because codec/write work dominates the small window.
- Baseline DLL SHA-256 `509CE89DED16C433313A9456115C4B3C686D3487D0C52D26AF4C682FFF7090BE`; final DLL `A58DB25FC9EEF19F73C0630030514511A69C879F670E98FBB2931CDAC6623053`. Baseline independently rebuilt from the preceding commit produced the same 12 oracle checksums and comparable timings.
- Принято после native diff review, исправления overflow-safe chroma bounds, независимого финального Dart прогона 17/17, format/analyze, `git diff --check` и Windows native `abi_blur_test.exe` + `abi_sanitizer_test.exe` (2/2; sanitizer instrumentation/allocation injection недоступны в этом Windows toolchain). Task commit записан в Git history.

# C-10 — Ускорен `yuv_mean_blur_v1`

- Исполнитель: GPT-6 Sol (T1). В legacy `0.2.4` найдены per-format mean implementations с другими radius, in-place writes, plane-specific YUV blur и integral image; их семантика не соответствует ABI v1. Принятая C-09 row/radius-bounded separable схема реализована локально в `yuv_mean_blur_v1.c`; C-09, Gaussian, shared kernel и ABI не менялись. Непромежуточное округление, edge replication, half-up divisor, BGRA alpha и odd-boundary ROI/chroma сохранены. Scratch: `width * (12 * min(height, 2r+1) + 24)` bytes, 24,720,000 bytes (~23.6 MiB) для 4000×3000/radius256; все allocations/checks до первой записи.
- Один адресный test проверяет I420/NV12/BGRA × radius1/3 × full/ROI (12 сценариев), bytewise Dart oracle и equality с `yuv_box_blur_v1`; также radius0/256, short/odd frames, padded strides и invalid/no-write cases. Замеры 321×241, 3 warmup + 8 timed calls. До → после мкс/вызов (speedup): I420 r1 full 11697→2758 (4.24×), ROI 12190→3191 (3.82×), r3 full 27672→2762 (10.02×), ROI 22695→3128 (7.26×); NV12 r1 full 10619→2619 (4.05×), ROI 10423→2883 (3.62×), r3 full 26640→2631 (10.13×), ROI 20672→2905 (7.12×); BGRA r1 full 5081→1548 (3.28×), ROI 4767→1581 (3.02×), r3 full 13412→1554 (8.63×), ROI 9934→1587 (6.26×). Radius1 stays below ~10× because decode/write dominate the small 3×3 window.
- Baseline DLL SHA-256 `C6C6EA71CB92BCE2B8930B79CF9985EE2DFDF4A489E86758064B1761A9108498`; final DLL `499484F798D367666B703C4CE5080CBBA7EC88DE2226F1E40231A8D4E753279B`. Baseline was independently rebuilt from the pre-C10 commit; all oracle checksums matched the executor's baseline report.
- Принято после native diff review, независимого rebuild+baseline и final Release Dart теста 17/17, format/analyze/diff-check и Windows native blur/sanitizer harnesses (2/2; OS toolchain не включает ASan/UBSan и allocation injection). Task commit записан в Git history.
