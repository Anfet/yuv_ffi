# yuv_ffi: проваленные test cases

Этот файл — единый журнал фактически воспроизведённых падений. План исправлений и владельцы задач находятся в `todo.md`.

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
| F-007 | CHROME-RUNNER-HANG-001 | Web/Chrome | OPEN | P0 | YUV-02 | Даже минимальный Flutter Web test зависает на стадии `loading` |
| F-008 | WASM-LOADER-RETRY-001 | Web/Chrome | READY FOR RETEST | P1 | YUV-21 | Мёртвый `<script>` остаётся в DOM, поэтому retry загрузчика всегда падает |

## Текущее состояние reference matrix

- Source: `test/assets/test_pattern_512.png`
- Source SHA-256: `a48d5d2959a4d86f3f036fd704acc3726a12aaa66de825f738b3fa8b7e5f631a`, подтверждён YUV-10.
- Manifest: `test/reference/test_pattern_512/manifest.json`, 119 cases, SHA-256 `3560e965300ee39eab7599d508849a7b3872b8a2330075962a3f4072093f4403`.
- Native reference run: Windows x64, 65/119 passed, 54/119 failed; полный список ниже в секции YUV-11.
- Web reference run: `NOT RUN` — выполнит YUV-12.
- Последняя сверка полноты: native matrix сверена YUV-11; общую native/Web сверку выполнит YUV-13 после YUV-12.

Пока YUV-10…YUV-13 не выполнены, отсутствие asset-specific записей ниже не означает отсутствие дефектов.

---

## F-007 — минимальный Chrome test зависает на `loading`

- Case ID: `CHROME-RUNNER-HANG-001`
- Статус: OPEN
- Обнаружено: 2026-09-13
- Commit: `f6d403c` + рабочий YUV-01 candidate
- Backend: Web / Chrome на Windows x64
- Environment: Flutter 3.38.10, Dart 3.10.9, headless Chrome 148
- Source image: не требуется
- Operation: запуск минимального `flutter_test` через Chrome platform runner
- Fix task: YUV-02

### Диагностический case

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Chrome runner executes a minimal Flutter test', () {
    expect(kIsWeb, isTrue);
  });
}
```

Case намеренно не импортирует `yuv_ffi`, не вызывает `YuvFfi.ensureInitialized()` и не загружает WASM. Постоянный sentinel не оканчивается на `_test.dart`, чтобы не попадать в обычный VM discovery.

### Команда

```powershell
flutter test --no-pub --platform chrome test/web/web_platform_sentinel.dart --reporter expanded
```

### Ожидалось

Один минимальный test регистрируется, выполняется в Chrome и завершается с exit `0`.

### Получено

Runner запустил headless Chrome, но более 90 секунд не продвинулся дальше:

```text
00:00 +0: loading D:/.projects/yuv_ffi/test/web/web_platform_sentinel.dart
```

Процесс остановлен вручную, exit `1`. Полный `test/web` проявляет то же поведение на первом test file. При этом `flutter build web --no-pub` для example успешно завершился, поэтому F-007 отделён от исходного compile blocker F-001.

### Артефакты и метрики

- Зарегистрированных/выполненных tests: `0`
- Время без прогресса: `>90 s`
- Импортов package/WASM в контрольном case: `0`
- Headless Chrome process: создан runner-ом
- Оставшиеся диагностические процессы и временный test file: удалены после прогона

### Retest

YUV-02 должен сначала воспроизвести минимальный case с verbose runner diagnostics, проверить совместимость Flutter test runner/Chrome и только затем полный `test/web`. Не менять production-код плагина, пока минимальный test без `yuv_ffi` не запускается.

Постоянный sentinel после YUV-02 находится в `test/web/web_platform_sentinel.dart`. Он не оканчивается на `_test.dart`, поэтому не попадает в стандартный VM discovery, но поддерживает explicit запуск через `flutter test --platform chrome <path>`.

### Resolution

- Fix commit: не заполнен
- Minimal Chrome retest: локально reproduces the same `loading` hang on Windows Flutter 3.38.10; F-007 остаётся `OPEN`.
- Flutter 3.44.9 retest, Windows x64: sentinel также оставался на `loading`
  более 60 секунд, после чего был остановлен вручную; tests executed: 0.
- Full `test/web` retest: не заполнен

### Диагноз и дальнейшие действия

Локальное проявление F-007 воспроизводится и после обновления с Flutter 3.38.10
до 3.44.9, поэтому прежняя рекомендация только обновить SDK недостаточна. Это
по-прежнему не доказанный дефект плагина: минимальный case не импортирует
`yuv_ffi`. Обязательный gate закреплён на Flutter 3.44.9 и использует Linux CI
runner. F-007 нельзя переводить в `RESOLVED` без успешного автоматического CI
evidence либо отдельного устранения Windows runner issue.

Asset-dependent Web runtime checks больше не используют этот runner: YUV-02
переводит обязательный bootstrap в `example/integration_test` + `flutter
drive`, где существует bundle package assets. Сам F-007 остаётся `OPEN`, пока
не будет отдельно воспроизведён и устранён Flutter `flutter test --platform
chrome` runner issue; это не должно блокировать integration gate.

Локальная попытка `flutter drive` 2026-09-14 (Windows 10 x64, Flutter 3.44.9,
Chrome/ChromeDriver 148.0.7778.179) дошла до `Waiting for connection from
debug service on Web Server` и была остановлена без зарегистрированного test.
Она не является ни успешным Web evidence, ни новым проявлением F-007: это
другая execution path, которую требуется подтвердить required Linux CI run.

---

## F-008 — мёртвый `<script>` делает retry загрузчика невозможным

- Case ID: `WASM-LOADER-RETRY-001`
- Статус: `READY FOR RETEST`
- Обнаружено: 2026-09-14, независимым ревью после run #26
- Commit: `dd786c4`
- Backend: Web / Chrome
- Environment: Flutter 3.44.9, Dart 3.12.2
- Source image: не требуется, дефект на уровне загрузчика
- Operation: `YuvWasmLoader.ensureInitialized()` после неудачной загрузки скрипта
- Fix task: YUV-21

### Диагностический case

```dart
// Первая попытка: скрипта нет, браузер отдаёт onError.
await expectLater(
  YuvWasmLoader.ensureInitialized(scriptPath: '.../does_not_exist.js'),
  throwsA(isA<StateError>()),
);

// Вторая попытка с правильными путями обязана подняться.
await YuvWasmLoader.ensureInitialized();
expect(YuvWasmLoader.moduleIfInitialized, isNotNull);
```

### Ожидалось

Решение 2 карточки YUV-21: неудачная попытка не кэшируется, следующая явная
попытка выполняется заново и может завершиться успехом.

### Получено

Вторая попытка падала с сообщением о ненайденном
`createYuvFfiModule` — то есть с неверной причиной, маскирующей настоящую.

Причина по исходному коду: `_injectScriptOnce()` помечает вставленный `<script>`
атрибутом `data-yuv-ffi-wasm-loader` и выходит рано, если такой тег уже есть.
При ошибке загрузки тег оставался в документе, поэтому следующая попытка
пропускала инъекцию и искала factory, которого ни один скрипт не определил.

### Артефакты и метрики

- Web runtime result: `NOT RUN` на момент регистрации записи
- VM result: неприменимо — дефект существует только на Web execution path
- Почему не был обнаружен раньше: все шесть lifecycle-кейсов подменяли
  инициализатор через `debugSetInitializer`, то есть заменяли собой весь
  `_initialize` вместе с `_injectScriptOnce`, и ни разу не касались DOM

### Retest

YUV-21 должен выполнить оба новых case в required Chrome job: retry после
реальной ошибки загрузки скрипта завершается успехом, и восстановленный модуль
выполняет настоящую конверсию, а не просто возвращает не-null.

### Resolution

- Статус: `READY FOR RETEST`. Run #28 зелёный, но regression не изолирует
  удаление failed DOM tag от reuse ранее загруженной default factory.
- Fix commit: см. commit задачи YUV-21
- Исправление: в ветке `onError` тег удаляется (`script.remove()`) до завершения
  completer. Только в ветке ошибки: успешно загруженный скрипт — ровно то, что
  маркер и должен фиксировать.
- Web retest command/result: run
  [34789878937](https://github.com/Anfet/yuv_ffi/actions/runs/34789878937),
  таргет `wasm_loader_lifecycle_test.dart` — **failure**, оба новых case:
  `Expected: throws <StateError> / Actual: <_Future<YuvModule>>`.
  Попытка с несуществующим `scriptPath` не упала: к этому моменту предыдущий
  case уже загрузил настоящий модуль, поэтому в документе оставался валидный
  тег, а на `globalThis` — рабочий `createYuvFfiModule`. `_injectScriptOnce()`
  выходил рано, подложный путь не запрашивался, factory находился.
- Следствие: прогон **не подтверждает и не опровергает** исправление — ветка
  ошибки не выполнялась ни разу. Тесты исправлены отдельно
  (`debugRemoveInjectedScript()` + factory name, которого никто не определяет),
  повторный прогон требуется.
- Повторный Web retest: run
  [34790481198](https://github.com/Anfet/yuv_ffi/actions/runs/34790481198),
  таргет `wasm_loader_lifecycle_test.dart` — **success**, `All tests passed.`
  На этом таргете `TestFailure` 2 -> 0 против предыдущего прогона; ассерт
  `throwsA(isA<StateError>())`, который падал с `Actual: <_Future<YuvModule>>`,
  теперь проходит. Затем в том же case проходят `moduleIfInitialized != null` и
  `debugInitCount == 2`: тег удалён, поэтому успешная вторая инициализация
  возможна только через новую инъекцию. Второй case выполняет настоящую
  конверсию через WASM.
- Граница утверждения: `failRealInjection()` задаёт и несуществующий
  `scriptPath`, и несуществующее имя factory, а `flutter drive` не печатает
  вывод отдельных case, поэтому какая именно из двух причин дала первый
  `StateError` — по логу не видно. Доказано восстановление после неудачной
  попытки, которое до `script.remove()` было недостижимо по построению.
- Поправка независимого ревью после run #28: последнее утверждение неверно.
  Default `createYuvFfiModule` остаётся в `globalThis` после предыдущего
  успешного case, поэтому retry с default factory может пройти без повторной
  инъекции даже при оставшемся failed tag. Нужен отдельный assertion отсутствия
  marker tag после `onError` либо второй failed-path probe, доказывающий новую
  инъекцию.

---

## Шаблон новой записи

```text
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
