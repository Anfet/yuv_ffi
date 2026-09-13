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
| F-001 | WEB-COMPILE-001 | Web/Chrome | OPEN | P0 | YUV-01 | Настоящий Web test suite не компилируется из-за нетипизированного `Function.toJS` |
| F-002 | SWAP-NV-LUMA-001 | Native/Windows | OPEN | P1 | YUV-03 | Один `swapNv()` заменяет Y-плоскость нулями |
| F-003 | GET-BYTES-LENGTH-001 | Native/Windows | OPEN | P1 | YUV-14 | `getBytes()` возвращает backing buffer с 7 лишними байтами для I420 `3x3` |
| F-004 | BGRA-PADDED-CONSTRUCTOR-001 | Native/Windows | OPEN | P1 | YUV-15 | Валидная padded BGRA-плоскость вызывает внутренний `RangeError` |
| F-005 | BINDINGS-CACHE-001 | Native/Windows | OPEN | P1 | YUV-19 | Кэш `YuvFfiBindings` не заполняется, каждый вызов заново резолвит символы |
| F-006 | IMAGE-CACHE-KEY-001 | Native/Windows | OPEN | P1 | YUV-20 | Два provider одного неизменённого кадра образуют разные cache keys |

## Текущее состояние reference matrix

- Source: `test/assets/test_pattern_512.png`
- Source SHA-256: `a48d5d2959a4d86f3f036fd704acc3726a12aaa66de825f738b3fa8b7e5f631a` — YUV-10 должен подтвердить его в manifest.
- Manifest: `NOT CREATED` — заполнит YUV-10.
- Native reference run: `NOT RUN` — выполнит YUV-11.
- Web reference run: `NOT RUN` — выполнит YUV-12.
- Последняя сверка полноты: `NOT RUN` — выполнит YUV-13.

Пока YUV-10…YUV-13 не выполнены, отсутствие asset-specific записей ниже не означает отсутствие дефектов.

---

## F-001 — Web suite не компилируется

- Case ID: `WEB-COMPILE-001`
- Статус: OPEN
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

- Fix commit: не заполнен
- Retest command/result: не заполнен

---

## F-002 — native `swapNv()` уничтожает luma

- Case ID: `SWAP-NV-LUMA-001`
- Статус: OPEN
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

YUV-03 должен добавить постоянный regression test. YUV-11 должен повторить проверку на `test/assets/test_pattern_512.png` и сравнить:

- Y после первого swap — exact;
- каждую chroma-пару после первого swap — exact reverse;
- Y и chroma после второго swap — exact исходному;
- identity/format/dimensions — без изменений.

### Resolution

- Fix commit: не заполнен
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

- Fix commit: не заполнен
- Native retest command/result: не заполнен
- Web retest command/result: не заполнен
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

### Resolution

- Fix commit: не заполнен
- Native retest command/result: не заполнен
- Web retest command/result: не заполнен
- Full `test_pattern_512.png` case result: не заполнен

---

## F-005 — кэш bindings не заполняется

- Case ID: `BINDINGS-CACHE-001`
- Статус: OPEN
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

- Fix commit: не заполнен
- Native retest command/result: не заполнен
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

- Fix commit: не заполнен
- Native retest command/result: не заполнен
- Web retest command/result: не заполнен
- Full `test_pattern_512.png` case result: не заполнен

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
