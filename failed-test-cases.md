# yuv_ffi: проваленные test cases

Этот файл — единый журнал фактически воспроизведённых падений. План исправлений
и владельцы задач находятся в `todo.md` либо `todo-waitlist.md`.

После независимого принятия fix-задачи ревьюер удаляет связанную запись целиком:
строку сводки и полную секцию, если она есть. Журнал содержит только актуальные
падения; доказательства принятого исправления находятся в task commit, tests и
Git history.

## Статусы

- `OPEN` — падение воспроизводится, исправление не принято.
- `IN FIX` — связанная задача находится в работе.
- `READY FOR RETEST` — исправление готово, нужен независимый повторный прогон.
- `WONTFIX` — только по явному решению владельца с записанным обоснованием.

## Сводка

| Failure ID | Case ID | Backend | Статус | Приоритет | Fix task | Кратко |
|---|---|---|---|---|---|---|
| F-009 | WEB-PLANAR-REFERENCE-001 | Web/WASM Chrome | OPEN | P1 | YUV-13 | I420/NV21 расходятся с эталоном на Web; BGRA совпадает |
| F-010 | WEB-MATRIX-ABORT-001 | Web/WASM Chrome | OPEN | P1 | YUV-40 | Прогон матрицы обрывается без сообщения на 20-м case, 100/119 не исполнены |

## Текущее состояние reference matrix

- Source: `test/assets/test_pattern_512.png`
- Source SHA-256: `a48d5d2959a4d86f3f036fd704acc3726a12aaa66de825f738b3fa8b7e5f631a`, подтверждён YUV-10.
- Manifest: `test/reference/test_pattern_512/manifest.json`, 119 cases, SHA-256 `3560e965300ee39eab7599d508849a7b3872b8a2330075962a3f4072093f4403`.
- Native reference run: Windows x64, 65/119 passed, 54/119 failed; полный список ниже в секции YUV-11.
- Web reference run: частичный, 2026-09-14. Исполнено 19/119, passed 7, failed 12,
  остальные 100 не исполнены из-за обрыва (F-010). Полного Web-прогона пока нет.
- Последняя сверка полноты: native matrix сверена YUV-11; общую native/Web сверку выполнит YUV-13 после YUV-12.

Пока YUV-10…YUV-13 не выполнены, отсутствие asset-specific записей ниже не означает отсутствие дефектов.

---

## F-009 — Web/WASM расходится с эталоном на I420 и NV21

- Case ID: `WEB-PLANAR-REFERENCE-001`
- Статус: OPEN
- Обнаружено: 2026-09-14
- Commit: `2ae1dc3` (HEAD), последний commit по C-исходникам `3524f05`
- Backend: Web / WASM, Chrome 153.0.8010.37 на Windows x64
- Environment: Flutter 3.38.10, Dart 3.10.9
- WASM: `assets/wasm/yuv_ffi.wasm` sha256
  `61b6c52d9aca319ed575cf403729d8684fa8ea5cc99f4d36abc638523e495569`;
  `yuv_ffi.js` sha256 `96576b243c3407fbb934a523a149fede8fbb0894491b3b3c702ee3921b8331a3`.
  Пересобран `bash ./tool/wasm/build_wasm.sh` (exit 0), diff артефактов пустой.
- Source image: `test/assets/test_pattern_512.png`, sha256
  `a48d5d2959a4d86f3f036fd704acc3726a12aaa66de825f738b3fa8b7e5f631a`
- Suite: `example/integration_test/reference_web_conversions_test.dart`
- Fix task: YUV-13 (классификация; отдельный fix task только после полной сверки)

### Воспроизведение

```powershell
Push-Location example
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/reference_web_conversions_test.dart -d chrome
Pop-Location
```

Провенанс прогона: `YUV-12 web provenance: kIsWeb=true, cases=119`.

### Факт

Исполнено 19/119 (обрыв — см. F-010), из них passed 7, failed 12.
Все 12 падений — I420/NV21. Все 5 BGRA-кейсов прошли с `mae=0.000 max=0`,
включая padded, то есть Web/BGRA совпадает с эталоном побайтово.

Failed case IDs:

```text
CONSTRUCT-I420-TIGHT       CONSTRUCT-I420-PADDED
OUTPUT-TO-BGRA-I420-TIGHT  OUTPUT-TO-BGRA-I420-PADDED
CONSTRUCT-NV21-TIGHT       CONSTRUCT-NV21-PADDED
OUTPUT-TO-BGRA-NV21-TIGHT  OUTPUT-TO-BGRA-NV21-PADDED
FORMAT-TO-BGRA-I420        FORMAT-TO-BGRA-NV21
FORMAT-TO-I420-BGRA-TIGHT  FORMAT-TO-I420-NV21-TIGHT
```

Три различимые группы:

1. **Расхождение при конструировании.** `CONSTRUCT-I420-TIGHT` падает в
   `_assertPlaneReference` по sha256 плоскости:
   expected `e2b4a0192095db1c5f96b4bfc524c22d283181d3921b07409dc58db99fe3c5e2`,
   actual `bda27b969a63634a0a6125bdcadfa453f1d0c8efe3495747ed1b3d68fda73462`,
   differ at offset 0. Никакая операция ещё не выполнялась — расходится сама
   раскладка планарных плоскостей.
2. **Метрики вне допуска `yuvRoundTrip`** (`mae<=18`, `max<=160`):
   - `OUTPUT-TO-BGRA-I420-TIGHT`: `mae=44.469 max=255 p99=255 outside=101888 alpha=0`
   - `FORMAT-TO-BGRA-I420`: `mae=44.469 max=255 p99=255 outside=101888 alpha=0`
   - `FORMAT-TO-I420-BGRA-TIGHT`: `mae=10.233 max=144 p99=144 outside=17408 alpha=0`
3. **Геометрия.** `FORMAT-TO-I420-NV21-TIGHT`: `Expected: <256>, Actual: <512>`
   в `_assertPlaneReference`.

### Границы утверждения

Сравнение native/Web не проводилось: это задача YUV-13. Native-прогон той же
матрицы (Windows x64) дал 65/119 passed, поэтому часть этих падений может
совпадать с уже известными native-дефектами, а часть быть Web-специфичной.
Без полного Web-прогона (блокирует F-010) разделить их нельзя.

Production behavior и tolerances в рамках YUV-12 не менялись.

---

## F-010 — прогон Web-матрицы обрывается без сообщения на 20-м case

- Case ID: `WEB-MATRIX-ABORT-001`
- Статус: OPEN
- Обнаружено: 2026-09-14
- Commit: `2ae1dc3` (HEAD)
- Backend: Web / WASM, Chrome 153.0.8010.37 на Windows x64
- Environment: Flutter 3.38.10, Dart 3.10.9
- Suite: `example/integration_test/reference_web_conversions_test.dart`
- Fix task: YUV-40 (изолированная диагностика; не production fix)

### Факт

Цикл по 119 cases печатает результат каждого case через `debugPrint` и ловит
все исключения через `catch (error, stackTrace)`. После 19-го case
(`FORMAT-TO-I420-NV21-TIGHT`, зафиксирован как FAILED) 20-й case
`FORMAT-TO-NV21-BGRA-TIGHT` не напечатал **ни PASS, ни FAIL**, и исполнение
прекратилось. Оставшиеся 100 cases не исполнены.

Признаки:

- строки `YUV-12 summary ... executed=... passed=... failed=...` в логе нет —
  цикл не дошёл до конца;
- счётчик runner остался `+0`, финального `All tests passed` / `Some tests
  failed` нет;
- в логе нет ни timeout, ни pending timer, ни потери соединения с debug service;
- прогон завершился сам: `Application finished.`, затем `EXIT=1`.

### Гипотеза

Так как per-case `catch` перехватывает любое `Object`, отсутствие записи
означает, что исполнение прервано некатчабельно для этого блока: WASM trap либо
`Error`, убивающий isolate. Для подтверждения нужен прицельный прогон только
`FORMAT-TO-NV21-BGRA-TIGHT` с захватом консоли браузера.

### Влияние

Блокирует DoD YUV-12: полный failure log недостижим, 100/119 cases не имеют
результата. До устранения нельзя ни закрыть YUV-12, ни выполнить сверку
native/Web (YUV-13).

---

## F-XXX — <краткое название>

- Case ID: <ID из reference manifest или infrastructure ID>
- Статус: OPEN
- Обнаружено: YYYY-MM-DD
- Commit: <полный hash>
- Backend: <Native/Web + OS/browser/arch>
- Environment: <Flutter/Dart/compiler versions>
- Binary/WASM provenance: <как собран и из какого commit>
- Source image: test/assets/test_pattern_512.png
- Source SHA-256: <hash>
- Operation: <method + parameters + input format>
- Fix task: <YUV-XX или NOT ASSIGNED>

### Команда
<точная воспроизводимая команда>

### Ожидалось
<expected format/dimensions/hash/bytes>

### Получено
<actual format/dimensions/hash/bytes>

### Метрики
- MAE: <value>
- Maximum channel error: <value>
- Percentile error: <value>
- Pixels outside threshold: <count/total>
- Alpha mismatches: <count>

### Артефакты
- Expected: <path вне build/>
- Actual: <path вне build/>
- Diff: <path вне build/>
- Log: <path вне build/ или inline excerpt>

### Resolution
- Fix commit: не заполнен
- Retest command/result: не заполнен
```

---

## YUV-11 — native reference matrix (2026-09-13)

- Case IDs: 54 failed / 119 manifest cases; 65 passed.
- Статус: OPEN (диагностика; production-код не изменялся).
- Backend: native Windows x64 (`Abi.windowsX64`).
- Environment: Flutter 3.38.10, Dart 3.10.9.
- Native binary: `D:\.projects\yuv_ffi\yuv_ffi.dll` (локальная ignored DLL, 135 680 bytes, last write UTC `2026-09-13 12:27:23`). Способ сборки не подтверждён; это не clean-checkout/CI evidence.
- Native binary SHA-256: `2093291b06f64c49f26a212b299d9fc41d405e334cb3afc97be403958240543d`.
- Source: `test/assets/test_pattern_512.png`, SHA-256 `a48d5d2959a4d86f3f036fd704acc3726a12aaa66de825f738b3fa8b7e5f631a`.
- Expected: независимые pure-Dart fixtures из `test/reference/test_pattern_512/manifest.json` (YUV-10), не получены из DLL.
- Command: `flutter test --no-pub test/reference_native_conversions_test.dart --reporter expanded`.
- Harness corrections included in this run: NV useful row bytes `chromaWidth * 2`; plane geometry/strides проверяются всегда, exact SHA — для exact manifest cases; tolerance cases use numeric image metrics; outside-threshold is counted per pixel; in-place identity/return and source immutability are asserted.

### Failure groups

Metrics use `MAE / max channel error / p99 channel error / pixels outside threshold / alpha mismatches`; expected limits are those predeclared in YUV-10 (not tuned from this run).

1. **Padded construction and default native stride (3 cases).**
   - `CONSTRUCT-BGRA8888-PADDED`: expected rowStride `2064`, actual `2048` (expected padded plane length `1056768`, actual tight `1048576`).
   - `FORMAT-TO-I420-NV21-TIGHT`, `FORMAT-TO-I420-NV21-PADDED`: expected chroma rowStride `256`, actual `512` (native output uses default I420 chroma stride instead of the manifest destination stride).

2. **YUV conversion envelope (5 cases).** Expected `max<=160`, `p99<=96` for `INPUT-FROM-RGBA-NV21`; expected `max<=96`, `p99<=48` for the `FORMAT` cases. `INPUT-FROM-RGBA-NV21`: `MAE 35.618 / max 255 / p99 255 / outside 58880 / alpha 0`. `FORMAT-TO-I420-BGRA-TIGHT`, `FORMAT-TO-NV21-BGRA-TIGHT`, `FORMAT-TO-I420-BGRA-PADDED`, `FORMAT-TO-NV21-BGRA-PADDED`: each `MAE 10.233 / max 144 / p99 144 / outside 17408, 0, 17408, 0 respectively / alpha 0`.

3. **Effects (6 cases).** Exact expected output was not met:
   - `EFFECT-GRAYSCALE-BGRA8888`: expected `MAE/max/p99/outside = 0/0/0/0`, actual `0.264/1/1/92416/0`.
   - `EFFECT-BLACKWHITE-BGRA8888`: expected exact, actual `1.121/255/0/1536/0`.
   - `EFFECT-BLACKWHITE-I420`, `EFFECT-BLACKWHITE-NV21`: expected `max<=96`, actual each `0.747/255/0/1024/0`.
   - `EFFECT-NEGATE-I420`, `EFFECT-NEGATE-NV21`: expected `max<=96`, actual each `8.152/134/134/17408/0`.

4. **Gaussian blur (4 cases).** Expected blur limits `MAE<=4`, `max<=24`, `p99<=12`, alpha exact:
   - `BLUR-GAUSSIANBLUR-I420-GAUSSIAN_DEFAULT`, `BLUR-GAUSSIANBLUR-NV21-GAUSSIAN_DEFAULT`: each `8.831/134/88/57487/0`.
   - `BLUR-GAUSSIANBLUR-I420-GAUSSIAN_R3_S2`, `BLUR-GAUSSIANBLUR-NV21-GAUSSIAN_R3_S2`: each `9.190/113/92/56917/0`.

5. **Box blur (6 cases).** Expected blur limits `4/24/12` and alpha exact:
   - `BLUR-BOXBLUR-I420-BOX_DEFAULT`: `20.569/191/131/83632/0`.
   - `BLUR-BOXBLUR-NV21-BOX_DEFAULT`: `7.899/119/89/56224/0`.
   - `BLUR-BOXBLUR-I420-BOX_FULL`: `17.046/183/124/66025/0`.
   - `BLUR-BOXBLUR-NV21-BOX_FULL`: `6.269/117/61/46228/0`.
   - `BLUR-BOXBLUR-I420-BOX_RECT`: `6.108/183/129/21319/0`.
   - `BLUR-BOXBLUR-NV21-BOX_RECT`: `27.042/179/139/108200/0`.

6. **Mean blur (9 cases).** Expected blur limits `4/24/12` and alpha exact (the `NV21-MEAN_FULL` case has the stricter manifest MAE limit `24`):
   - `BLUR-MEANBLUR-BGRA8888-MEAN_DEFAULT`: `59.483/142/92/262135/262135`.
   - `BLUR-MEANBLUR-I420-MEAN_DEFAULT`: `8.780/166/104/50162/0`.
   - `BLUR-MEANBLUR-NV21-MEAN_DEFAULT`: `4.079/95/45/33380/0`.
   - `BLUR-MEANBLUR-BGRA8888-MEAN_FULL`: `28.963/78/45/256348/262108`.
   - `BLUR-MEANBLUR-I420-MEAN_FULL`: `17.125/183/122/67826/0`.
   - `BLUR-MEANBLUR-NV21-MEAN_FULL`: `2.639/89/28/13448/0` (the allowed blur maximum channel error is `24`; actual max is `89`).
   - `BLUR-MEANBLUR-BGRA8888-MEAN_RECT`: `130.024/255/255/262144/262144`.
   - `BLUR-MEANBLUR-I420-MEAN_RECT`: `6.263/183/129/22421/0`.
   - `BLUR-MEANBLUR-NV21-MEAN_RECT`: `20.811/188/129/78540/0`.

7. **Raw copy/getBytes/save-load alignment tail (12 cases).** Expected raw lengths are I420 `393216` and NV21 `393216` for tight cases; actual is `524288` for all six tight I420/NV21 cases. For padded `getBytes`, expected `399360`, actual `532480`. In each case the expected prefix is present, followed by alignment bytes; comparison reports `MAE Infinity / max 255 / p99 255 / outside = actual length / alpha 1`.
   - I420: `STATE-COPY-I420-NORMAL`, `STATE-COPY-I420-BLANK`, `BYTES-GET-I420-TIGHT`, `IO-SAVE-LOAD-I420-SINGLE_CHUNK`, `IO-SAVE-LOAD-I420-FRAGMENTED`; padded: `BYTES-GET-I420-PADDED`.
   - NV21: `STATE-COPY-NV21-NORMAL`, `STATE-COPY-NV21-BLANK`, `BYTES-GET-NV21-TIGHT`, `IO-SAVE-LOAD-NV21-SINGLE_CHUNK`, `IO-SAVE-LOAD-NV21-FRAGMENTED`; padded: `BYTES-GET-NV21-PADDED`.

8. **Odd custom strides (9 cases).** The native constructor ignores requested custom padding for BGRA and produces a different Y plane for I420/NV21:
   - `INPUT-ODD-CUSTOM-STRIDE-BGRA8888-1X1`: expected rowStride `11`, actual `4`.
   - `INPUT-ODD-CUSTOM-STRIDE-I420-1X1`, `INPUT-ODD-CUSTOM-STRIDE-NV21-1X1`: expected Y SHA `f1f374e0288da16df068374c68ed27e1650a1fbc91c371f619a51c4a4a59713f`, actual `097328e8c957de2428283954f6a1ee8ff7ad7def12e100a600178407f5decf24`.
   - `INPUT-ODD-CUSTOM-STRIDE-BGRA8888-3X5`: expected rowStride `19`, actual `12`.
   - `INPUT-ODD-CUSTOM-STRIDE-I420-3X5`, `INPUT-ODD-CUSTOM-STRIDE-NV21-3X5`: expected Y SHA `30b85dcb472bb9a0063f493daccc48163a6cce0824c8560111bb4bc34331a609`, actual `439dd8046337b52d15c3abbb68090c7557f81106459cfec7d90013e1c407c6f4`.
   - `INPUT-ODD-CUSTOM-STRIDE-BGRA8888-127X255`: expected rowStride `515`, actual `508`.
   - `INPUT-ODD-CUSTOM-STRIDE-I420-127X255`, `INPUT-ODD-CUSTOM-STRIDE-NV21-127X255`: expected Y SHA `5991e56291c3d7633107b14ec57135a1d327ecc60f59fd7677e1a2212aa8ed40`, actual `305c72b9ca7a54c806894e694f2f72a401a0fd9edc11450e8deb8dac857e87f5`.

   **RESOLVED, 2026-09-13:** all nine cases pass after `3524f05`
   (`fix: complete YUV-05 stride and odd-size safety`). The focused manifest
   run on Flutter 3.44.9 completed 9/9 with exact expected plane geometry and
   hashes. The historical failures above are retained as audit evidence.

### Scoped verification

- `flutter analyze --no-pub test/reference_native_conversions_test.dart` — passed.
- `dart format --output=none --set-exit-if-changed test/reference_native_conversions_test.dart` — passed.
- `git diff --check -- test/reference_native_conversions_test.dart failed-test-cases.md` — passed.

### Resolution

- Fix commit for the nine odd/custom-stride cases: `3524f05`. Other groups in
  this report remain assigned to their existing follow-up tasks.
- Follow-up: route geometry/custom-stride failures to YUV-04/YUV-05/YUV-15, raw alignment tails to YUV-07/YUV-14, and UV conversion failures to YUV-05. Effects and blur require отдельные native implementation tasks. Re-run this exact 119-case matrix after fixes.
