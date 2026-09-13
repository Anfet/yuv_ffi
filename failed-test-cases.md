# yuv_ffi: проваленные test cases

Этот файл — единый журнал фактически воспроизведённых падений. План исправлений и владельцы задач находятся в `todo.md`.

Запись не удаляется после исправления. Её статус меняется на `RESOLVED`, добавляются fix commit и evidence повторного успешного прогона.

## Статусы

- `OPEN` — падение воспроизводится, исправление не принято.
- `IN FIX` — связанная задача находится в работе.
- `READY FOR RETEST` — исправление готово, нужен независимый повторный прогон.
- `RESOLVED` — исходная команда и полный reference case прошли после исправления.
- `WONTFIX` — только по явному решению владельца с записанным обоснованием.

## Сводка

| Failure ID | Case ID | Backend | Статус | Приоритет | Fix task | Кратко |
|---|---|---|---|---|---|---|
| F-001 | WEB-COMPILE-001 | Web/Chrome | RESOLVED | P0 | YUV-01 | `Function.toJS` blocker устранён; package и example компилируются на Flutter 3.44.9 |
| F-002 | SWAP-NV-LUMA-001 | Native/Windows | RESOLVED | P1 | YUV-03 | `swapNv()` сохраняет Y и exact-переставляет chroma pairs |
| F-003 | GET-BYTES-LENGTH-001 | Native/Windows | READY FOR RETEST | P1 | YUV-14 | `getBytes()` возвращает backing buffer с 7 лишними байтами для I420 `3x3` |
| F-004 | BGRA-PADDED-CONSTRUCTOR-001 | Native/Windows | READY FOR RETEST | P1 | YUV-15 | Валидная padded BGRA-плоскость вызывает внутренний `RangeError` |
| F-005 | BINDINGS-CACHE-001 | Native/Windows | RESOLVED | P1 | YUV-19 | Повторные обращения переиспользуют один экземпляр `YuvFfiBindings` |
| F-006 | IMAGE-CACHE-KEY-001 | Native/Windows | READY FOR RETEST | P1 | YUV-20 | Два provider одного неизменённого кадра образуют разные cache keys |
| F-007 | CHROME-RUNNER-HANG-001 | Web/Chrome | OPEN | P0 | YUV-02 | Даже минимальный Flutter Web test зависает на стадии `loading` |

## Текущее состояние reference matrix

- Source: `test/assets/test_pattern_512.png`
- Source SHA-256: `a48d5d2959a4d86f3f036fd704acc3726a12aaa66de825f738b3fa8b7e5f631a`, подтверждён YUV-10.
- Manifest: `test/reference/test_pattern_512/manifest.json`, 119 cases, SHA-256 `3560e965300ee39eab7599d508849a7b3872b8a2330075962a3f4072093f4403`.
- Native reference run: Windows x64, 65/119 passed, 54/119 failed; полный список ниже в секции YUV-11.
- Web reference run: `NOT RUN` — выполнит YUV-12.
- Последняя сверка полноты: native matrix сверена YUV-11; общую native/Web сверку выполнит YUV-13 после YUV-12.

Пока YUV-10…YUV-13 не выполнены, отсутствие asset-specific записей ниже не означает отсутствие дефектов.

---

## F-001 — Web suite не компилируется

- Case ID: `WEB-COMPILE-001`
- Статус: RESOLVED
- Обнаружено: 2026-09-12
- Commit: `5f52fd14540a283da91a6d80e1fc7128bba1c796`
- Backend: Web / Chrome compiler
- Environment: Flutter 3.38.10, Dart 3.10.9, Windows host
- Source image: до исполнения `test_pattern_512.png` дело не дошло
- Fix task: YUV-01

### Команда

```powershell
flutter test --platform chrome test/web
```

### Ожидалось

Все Web test files компилируются и исполняются с `kIsWeb == true`.

### Получено

Компиляция остановилась до запуска test cases:

```text
lib/src/web/js_util_compat.dart:19:52: Error:
Functions converted via 'toJS' require a statically known function type,
but Type 'Function' is not a precise function type.
```

### Артефакты и метрики

- Exit code: `1`
- Executed reference cases: `0`
- Passed: `0`
- Failed: compile gate
- Skipped: неприменимо, suite не собран

### Retest

После YUV-01 повторить исходную команду. Запись можно закрыть только если suite компилируется, выполняется в Web environment и не проходит через `!kIsWeb` skip.

### Resolution

- Fix commits: `fa311d9`, `91ff7e9`
- Compile evidence на Flutter 3.44.9: настоящий package-importing
  `yuv_web_wasm_test.dart` более 60 секунд остаётся на общей browser `loading`
  стадии F-007 без исходного `Function.toJS` diagnostic.
- `flutter analyze --no-pub` и `flutter build web --no-pub` из `example/` —
  exit 0 после удаления несовместимого `material_design_icons_flutter`.
- Runtime Web suite остаётся отдельным F-007/YUV-02; это не повторное
  проявление устранённого compiler defect F-001.

---

## F-002 — native `swapNv()` уничтожает luma

- Case ID: `SWAP-NV-LUMA-001`
- Статус: RESOLVED
- Обнаружено: 2026-09-12
- Commit: `5f52fd14540a283da91a6d80e1fc7128bba1c796`
- Backend: Native / Windows x64
- Environment: Flutter 3.38.10, Dart 3.10.9
- Native library provenance: локальный игнорируемый root `yuv_ffi.dll`; clean-checkout provenance не подтверждён
- Source image: диагностический белый RGBA `2x2`; полный `test_pattern_512.png` case добавит YUV-11
- Operation: один in-place `swapNv()`
- Fix task: YUV-03

### Case setup

```dart
final rgba = Uint8List.fromList(<int>[
  255, 255, 255, 255,
  255, 255, 255, 255,
  255, 255, 255, 255,
  255, 255, 255, 255,
]);
final image = YuvImage.nv21(2, 2)..fromRgba8888(rgba);
final originalY = Uint8List.fromList(image.yPlane.bytes);

image.swapNv();

expect(image.yPlane.bytes, orderedEquals(originalY));
```

### Ожидалось

`swapNv()` переставляет только соседние chroma bytes и сохраняет Y byte-for-byte.

```text
Expected Y: [235, 235, 235, 235]
```

### Получено

```text
Actual Y: [0, 0, 0, 0]
Which: at location [0] is <0> instead of <235>
```

### Артефакты и метрики

- Exit code: `1`
- Luma mismatches: `4/4`
- Maximum luma error: `235`
- Chroma comparison после первого swap: не была частью диагностического case
- Alpha/BGRA comparison: не была частью диагностического case

### Retest

YUV-03 добавила постоянные regression tests. YUV-11 должна повторить проверку на `test/assets/test_pattern_512.png` и сравнить:

- Y после первого swap — exact;
- каждую chroma-пару после первого swap — exact reverse;
- Y и chroma после второго swap — exact исходному;
- identity/format/dimensions — без изменений.

### Resolution

- Исправлено: 2026-09-13
- Fix commit: текущий commit YUV-03
- Реализация сохраняет Y одной deep copy, создаёт отдельный UV destination с исходным stride layout и переносит обратно готовые planes без повторного копирования.
- `flutter test --no-pub test/conversions_test.dart --plain-name "swapNv" --reporter expanded` — 4/4 passed.
- `flutter test --no-pub --reporter expanded` — 33/33 passed.
- Проверены exact Y после одного/двух swap, exact reverse chroma pairs, I420 conversion path, in-place identity и padded Y/UV layout.
- `flutter analyze --no-pub lib test`, format-check и `git diff --check` — passed.
- Native C и generated bindings не изменялись.
- Retest command/result: не заполнен
- Full `test_pattern_512.png` case result: не заполнен

---

## F-003 — `getBytes()` возвращает выровненный хвост

- Case ID: `GET-BYTES-LENGTH-001`
- Статус: OPEN
- Обнаружено: 2026-09-13
- Commit: `5f52fd14540a283da91a6d80e1fc7128bba1c796`
- Backend: Native / Windows x64; Web имеет тот же дефект по инспекции исходного кода, runtime-retest заблокирован F-001
- Environment: Flutter 3.38.10, Dart 3.10.9
- Source image: синтетический I420 `3x3`; полный `test_pattern_512.png` case добавят YUV-11/YUV-12
- Operation: `YuvImage.i420(3, 3).getBytes()`
- Fix task: YUV-14

### Диагностический case

```dart
final image = YuvImage.i420(3, 3);
final expectedLength = image.planes.fold<int>(
  0,
  (sum, plane) => sum + plane.bytes.length,
);

expect(expectedLength, 25);
expect(image.getBytes(), hasLength(expectedLength));
```

### Команда

Case был воспроизведён временным тестом, удалённым после аудита:

```powershell
flutter test test/_audit_new_findings_test.dart
```

### Ожидалось

`getBytes()` возвращает ровно последовательную конкатенацию всех плоскостей:

```text
Expected length: 25
```

### Получено

```text
Actual length: 32
Unexpected tail: 7 bytes
```

Причина по исходному коду: результат `WriteBuffer.done()` преобразуется через весь backing buffer, включая alignment padding, вместо фактического `ByteData` view.

### Артефакты и метрики

- Exit code: `1`
- Length mismatch: `+7`
- Содержимое лишнего хвоста: нулевые байты в воспроизведённом case
- Web runtime result: `NOT RUN`, до устранения F-001

### Retest

YUV-14 должен добавить постоянные regression cases для нечётных `1x1`, `3x3`, `127x255`, контрольного `512x512`, всех форматов и padded planes. Для каждого case длина обязана точно равняться сумме длин плоскостей, а содержимое — их последовательной byte-for-byte конкатенации без хвоста.

### Resolution

- Статус: `READY FOR RETEST`. Native сторона исправлена и покрыта постоянными
  regression cases; `RESOLVED` требует настоящего Chrome прогона, который
  остаётся заблокированным F-007/YUV-02.
- Fix commit: см. commit задачи YUV-14 (`fix: removed the getBytes alignment tail`)
- Исправление: все три backend (`io`, `web`, `yuv_stub`) вызывают общий
  `YuvPlaneBytes.concat()`, выделяющий ровно `sum(plane.bytes.length)` байт,
  вместо `WriteBuffer.done().buffer.asUint8List()`.
- Native retest command/result:
  `flutter test test/conversions_test.dart --plain-name "getBytes"` — exit 0,
  10 tests passed (Windows 10 x64 / AMD64, Flutter 3.38.10).
- Regression доказан: те же 10 cases на неисправленном
  `lib/src/yuv/impl/io/yuv_image.dart` дают 1 passed / 9 failed, включая
  исходный F-003 case `Expected: length of <25> / Actual: length of <32>`.
- Web retest command/result: `NOT RUN`, до устранения F-007/YUV-02. Контрактные
  cases добавлены в `test/web/wasm_parity_edge_cases_test.dart` и выполнятся,
  как только Chrome runner заработает.
- Full `test_pattern_512.png` case result: не заполнен

---

## F-004 — padded BGRA-плоскость ломает конструктор

- Case ID: `BGRA-PADDED-CONSTRUCTOR-001`
- Статус: OPEN
- Обнаружено: 2026-09-13
- Commit: `5f52fd14540a283da91a6d80e1fc7128bba1c796`
- Backend: Native / Windows x64; Web по инспекции исходного кода принимает тот же input через `copy()`, runtime-retest заблокирован F-001
- Environment: Flutter 3.38.10, Dart 3.10.9
- Source image: синтетическая валидная padded BGRA-плоскость `2x2`
- Operation: `YuvImage.bgra(2, 2, planes: [YuvPlane(2, 16, 4)])`
- Fix task: YUV-15

### Диагностический case

```dart
expect(
  () => YuvImage.bgra(
    2,
    2,
    planes: <YuvPlane>[YuvPlane(2, 16, 4)],
  ),
  returnsNormally,
);
```

Вход корректен: `height = 2`, `rowStride = 16`, `pixelStride = 4`, выделено `32` байта; полезные `8` байт каждой строки помещаются с padding.

### Команда

Case был воспроизведён временным тестом, удалённым после аудита:

```powershell
flutter test test/_audit_new_findings_test.dart
```

### Ожидалось

Конструктор принимает валидную padded plane, делает независимую копию и сохраняет согласованный контракт layout без исключения.

### Получено

```text
RangeError (end): Invalid value: Not in inclusive range 0..16: 32
```

Исключение возникает не на валидации публичного аргумента, а внутри `YuvPlane` при копировании выровненного backing buffer, полученного после repack через `WriteBuffer`.

### Артефакты и метрики

- Exit code: `1`
- Input bytes: `32`
- Useful BGRA bytes: `16`
- Native result: непредусмотренный `RangeError`
- Web runtime result: `NOT RUN`, до устранения F-001
- Source-level parity: нарушен — Web сохраняет padded plane через `copy()`, Native пытается repack

### Retest

YUV-15 должен добавить постоянные Native/Web tests для tight и padded BGRA planes. Валидный padding должен приниматься одинаково, а действительно невалидная геометрия — отклоняться на границе API предсказуемым `ArgumentError`, без внутреннего `RangeError`.

### Изменение симптома до исправления

На момент YUV-15 исходный `RangeError` уже не воспроизводился: после принятой YUV-04
конструктор перестал падать, но вместо этого **молча понижал** валидную padded plane
до tight:

```text
YuvImage.bgra(2, 2, planes: [YuvPlane(2, 16, 4)])
до YUV-15:  rowStride=8,  bytes=16   // padding отброшен без предупреждения
generic:    rowStride=16, bytes=32   // backend contracts расходились
```

Тихая потеря declared layout хуже исключения, поэтому запись остаётся валидной:
дефект тот же (конструктор не уважает валидный padded layout), изменилось только
его проявление.

### Resolution

- Статус: `READY FOR RETEST`. Native сторона исправлена и покрыта постоянными
  regression cases; `RESOLVED` требует настоящего Chrome прогона, который
  остаётся заблокированным F-007/YUV-02.
- Fix commit: см. commit задачи YUV-15 (`fix: kept the declared layout of a padded BGRA plane`)
- Исправление: `YuvImageImpl.bgra` теперь делегирует generic-конструктору, поэтому
  оба entry point используют один validator и одну deep-copy семантику. `copy()`
  во всех трёх backend сохраняет declared geometry, а `copy(blank: true)`
  обнуляет всю выделенную plane вместо схлопывания padding до tight.
- Native retest command/result:
  `flutter test test/conversions_test.dart --plain-name "padded BGRA"` — exit 0,
  6 tests passed (Windows 10 x64 / AMD64, Flutter 3.38.10).
- Full `test_pattern_512.png` case result: `BYTES-GET-BGRA8888-PADDED` теперь
  сравнивается padded-к-padded (`raw length=1056768/1056768`, mae=0.000) против
  собственного `rawPlaneReference` манифеста (`rowStride: 2064`). Эталонные
  значения не перегенерировались.
- Web retest command/result: `NOT RUN`, до устранения F-007/YUV-02. Контрактные
  cases добавлены в `test/web/wasm_parity_edge_cases_test.dart`.

---

## F-005 — кэш bindings не заполняется

- Case ID: `BINDINGS-CACHE-001`
- Статус: RESOLVED
- Обнаружено: 2026-09-13
- Commit: `5f52fd14540a283da91a6d80e1fc7128bba1c796`
- Backend: Native / Windows x64; Web не затронут, там своя WASM-обвязка
- Environment: Flutter 3.38.10, Dart 3.10.9
- Source image: не требуется, дефект на уровне загрузчика
- Operation: повторное обращение к `ffiBingings`
- Fix task: YUV-19

### Диагностический case

```dart
// lib/src/loader/impl/loader_io.dart
YuvFfiBindings? _ffiBingings;
YuvFfiBindings get ffiBingings => _ffiBingings ?? YuvFfiBindings(library);
```

В поле `_ffiBingings` нет ни одной записи во всём `lib/`: объявление и чтение присутствуют, присваивания нет. Использован `??` вместо `??=`.

### Команда

Case был воспроизведён временным тестом, удалённым после аудита:

```powershell
flutter test test/_audit_bindings_cache_test.dart
```

### Ожидалось

Экземпляр `YuvFfiBindings` создаётся один раз на процесс, и `late final` кэш символов внутри сгенерированного класса переиспользуется.

### Получено

Новый экземпляр на каждое обращение; кэш символов отбрасывается. Замер 300 обращений к одному и тому же символу:

```text
uncached 300 lookups:  38923 us
cached   300 lookups:     12 us
```

### Артефакты и метрики

- Обращений к `ffiBingings.*` в `lib/src/yuv/impl/io/yuv_image.dart`: `40`
- Замедление повторного lookup: `~3200x`
- Функциональной ошибки нет: дефект производительности на горячем пути
- Сгенерированный `yuv_ffi_bingings.dart` корректен и не является причиной

### Retest

YUV-19 должен добавить regression, фиксирующий identity: N обращений к `ffiBingings` возвращают один созданный экземпляр. Повторный benchmark допустим как диагностическое evidence, но не как pass/fail assertion с временным порогом.

### Resolution

- Исправлено: 2026-09-13
- Fix commit: текущий commit YUV-19
- Native retest command/result: `flutter test --no-pub test/loader_io_test.dart --reporter expanded` — 1/1 passed, Windows x64, локальный `yuv_ffi.dll`
- Identity: три последовательных обращения к `ffiBingings` возвращают один объект
- Linux/host без native artifact: case явно skipped вместо падения полного VM suite
- Web retest command/result: не применимо
- Full `test_pattern_512.png` case result: не применимо

---

## F-006 — provider одного кадра не переиспользует cache key

- Case ID: `IMAGE-CACHE-KEY-001`
- Статус: OPEN
- Обнаружено: 2026-09-13
- Commit: `5f52fd14540a283da91a6d80e1fc7128bba1c796`
- Backend: Native / Windows x64; Web имеет тот же widget-код, runtime-retest заблокирован F-001
- Environment: Flutter 3.38.10, Dart 3.10.9
- Source image: синтетический BGRA `4x4`; полный `test_pattern_512.png` case добавят YUV-11/YUV-12
- Operation: `YuvImageWidget` / `YuvImageProvider`
- Fix task: YUV-20

### Диагностический case

```dart
final image = YuvImage.bgra(4, 4);
final first = YuvImageProvider(image);
final second = YuvImageProvider(image);

expect(first, equals(second));
expect(first.hashCode, equals(second.hashCode));
```

### Команда

Case был воспроизведён временным тестом, удалённым после аудита:

```powershell
flutter test test/_audit_image_cache_test.dart
```

### Ожидалось

Два provider для одного неизменённого кадра образуют одинаковый ключ `PaintingBinding.instance.imageCache` и позволяют переиспользовать декодированный `ui.Image`.

### Получено

```text
two providers same image equal? false
hashCodes equal?                false
```

`YuvImageProvider` не переопределяет `==`/`hashCode`, а `obtainKey()` возвращает `this`. Каждый rebuild создаёт новый ключ и повторяет полную конверсию в BGRA плюс `decodeImageFromPixels`.

### Артефакты и метрики

- Равенство двух provider неизменённого кадра: `false`
- Cache miss при создании нового provider следует из identity key и реализации Flutter `ImageCache`; фактическое число decode/conversion calls отдельным seam пока не измерено
- Обратный риск предлагаемого наивного исправления: равенство только по `image` вернёт устаревший кадр после in-place или прямой plane mutation
- Web runtime result: `NOT RUN`, до устранения F-001

### Retest

YUV-20 должен доказать оба сценария счётчиком фактических conversion/decode calls: cache hit для неизменённого кадра и обязательный refresh после штатной мутации. Отдельный case должен изменить `plane.bytes`, вызвать `markDirty()` и подтвердить refresh. Повторить на native и в реальном Chrome.

### Resolution

- Статус: `READY FOR RETEST`. Native сторона исправлена и покрыта постоянными
  regression cases; `RESOLVED` требует настоящего Chrome прогона, который
  остаётся заблокированным F-007/YUV-02.
- Fix commit: см. commit задачи YUV-20 (`fix: keyed the image cache by frame revision`)
- Исправление: в `YuvImage` добавлены `revision` и `markDirty()`.
  `YuvImageProvider` сохраняет revision snapshot при создании, а его
  `==`/`hashCode` строятся из `identityHashCode(image)` и этого snapshot.
- Счётчик фактических conversion calls добавлен в fake и подтверждает оба
  сценария, а не только равенство provider:
  - неизменённый кадр — `conversions` не растёт при rebuild (cache hit);
  - после `mutateInPlace()` — `conversions` растёт (обязательный refresh).
- Отдельный case меняет `plane.bytes`, проверяет, что ключ при этом ещё не
  изменился, затем вызывает `markDirty()` и подтверждает инвалидацию.
- Native retest command/result:
  `flutter test test/yuv_image_widget_test.dart` — exit 0, 11 tests passed;
  `flutter test test/yuv_image_revision_test.dart` — exit 0, 14 tests passed
  (Windows 10 x64 / AMD64, Flutter 3.38.10).
- Regression доказан: при откате только `lib/src/widgets/yuv_image_widget.dart`
  три cache-case падают, включая решающий «an unchanged frame is converted once
  across rebuilds».
- Web retest command/result: `NOT RUN`, до устранения F-007/YUV-02. Revision и
  `markDirty()` реализованы в web backend симметрично.
- Full `test_pattern_512.png` case result: не заполнен

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
