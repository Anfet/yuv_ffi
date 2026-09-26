# yuv_ffi 0.4.2 — ускорение YUV → BGRA

Текущий Windows Release/AOT замер полного публичного вызова на 1920×1080: NV12→BGRA **43,30–44,10 мс**, I420→BGRA **44,15–44,23 мс**. Это время включает Dart-подготовку, FFI, C-конвертацию и копирование результата; доля каждого этапа неизвестна. [Методика, 24 raw строки и checksum](doc/perf/results/conversion_windows_1080p_2026-09-26.md). Цель — ускорить `toBgraBytes()` и `toBgra()` без изменения результата и контракта ABI v1.

## Правила для каждой задачи

- Одна узкая правка или один изолированный эксперимент. Использовать один небольшой Dart runner, без общей матрицы. Сравнивать baseline и кандидат на одинаковых данных, размере, устройстве и сборке Release/AOT. Windows: 1920×1080; Pixel 3: 720×360, затем контрольный 1080p. Входной кадр и checksum фиксировать; подготовку кадра и проверку результата не включать в таймер.
- Сохранять raw samples, медиану, разброс, SHA исходников/сборки и абсолютный выигрыш в мс. Отдельно показывать C kernel и полный публичный вызов: выигрыш одного этапа нельзя выдавать за выигрыш функции целиком.
- Проверять byte-exact результат для NV12 и I420, alpha=255, нечётные размеры, row/pixel stride, padding, ошибки и освобождение памяти. После отчёта по каждой принятой задаче — отдельный коммит. Отрицательный результат также фиксировать; не переносить его в production.

## Активные задачи

| ID | Статус | Зависимость | Исполнитель; проверка | Конкретный результат |
| --- | --- | --- | --- | --- |
| BGRA-00 | DONE | — | T2 · GPT-5.6 Terra; T1 · GPT-6 Sol | Разложить NV12/I420→BGRA на входной Dart staging, выделение/обнуление destination, `yuv_convert_v1`, копирование результата и полный `toBgraBytes()`/`toBgra()`. Один Dart runner с прямым FFI замером ядра, те же входы и checksum; измерить Windows 1080p и Pixel 3 720×360. По отчёту выбрать порядок следующих задач. |
| BGRA-01 | DONE | BGRA-00: C значим | T2 · GPT-5.6 Terra; T1 · GPT-6 Sol | Оптимизировать только NV12-ветку `yuv_convert_to_bgra` в `src/yuv/abi/yuv_convert_v1.c`: вынести выбор формата из цикла, переиспользовать UV для пары Y, добавить быстрый tight путь при сохранении generic stride пути. Сравнить C и полный вызов; byte-exact, odd/padded/gapped и sanitizer проверки обязательны. |
| BGRA-02 | TODO | BGRA-00: C значим; BGRA-01 | T2 · GPT-5.6 Terra; T1 · GPT-6 Sol | Отдельно оптимизировать I420-ветку той же функции, переиспользуя U/V для соседних пикселей и не меняя целочисленную формулу BT.601. Те же тесты и замеры; проверить отсутствие регрессии NV12 после изменения общей функции. |
| BGRA-03 | TODO | BGRA-00: подготовка/zero-fill значимы | T1 · GPT-6 Sol; T2 · GPT-5.6 Terra | Проверить один Dart transport-кандидат: убрать лишнее обнуление только у полностью перезаписываемых байтовых буферов конвертации. Структуры ABI и ROI должны остаться инициализированными. Проверить allocator failure/atomicity, память и ускорение полного вызова; без выигрыша не переносить. |
| BGRA-04 | TODO | BGRA-00: copy-out значим | T1 · GPT-6 Sol; T2 · GPT-5.6 Terra | Изолированно проверить уменьшение копирования native BGRA результата в Dart без утечки или преждевременного освобождения. Сохранить независимость результата от источника, срок жизни буфера и публичное поведение; сравнить полный вызов и память. При риске контракта закрыть отрицательным выводом. |
| BGRA-05 | TODO | BGRA-01…04 или их обоснованное закрытие | T1 · GPT-6 Sol; T2 · GPT-5.6 Terra | Свести принятые варианты, повторить полный `toBgraBytes()` и `toBgra()` для NV12/I420 на Windows и Pixel 3, сравнить с исходными 43–44 мс на одинаковом 1080p входе. Зафиксировать итоговое время, выигрыш, checksum, память и оставшийся лимитирующий этап. |

### BGRA-00 — Executor Report

**Статус:** DONE
**Исполнитель:** T2 · GPT-5.6 Terra

Полный отчёт, методика и три раунда raw данных:
[bgra00_stage_breakdown_windows_1080p_2026-09-26.md](doc/perf/results/bgra00_stage_breakdown_windows_1080p_2026-09-26.md),
raw CSV — [bgra00_stage_breakdown_windows_1080p_raw.csv](doc/perf/results/bgra00_stage_breakdown_windows_1080p_raw.csv).
Новый read-only Dart FFI runner:
[speed_00_dart_ffi/test/yuv_convert_v1_bgra_stages_test.dart](speed_00_dart_ffi/test/yuv_convert_v1_bgra_stages_test.dart)
(не трогает native C, только раскладывает вызов на этапы через тот же ABI v1 struct layout, что и
существующий `yuv_convert_v1_test.dart`).

- Собран нативный `yuv_ffi.dll` на текущем HEAD `dcb336db590e25b7aa6103c2a98f6c2538e4ac2c`
  (release/0.4.2, native код не менялся с базового замера `3564f5f`), MSVC Release x64. SHA-256:
  `8F45897E07E08FDB32B87524E15BE75CEAF2EFA9CF06CDD83C3A69EC12676ABE`.
- Замерены 4 этапа `YuvAbiV1Runner._run` (staging источника, calloc+zero-fill destination,
  сам `yuv_convert_v1`, копирование результата) отдельно и как полная последовательность, для
  NV12→BGRA и I420→BGRA на 1920×1080, 30 замеров/этап, 3 раунда, byte-exact проверка каждого
  прогона по FNV-1a checksum против независимого oracle.
- Результат (медиана, округлено): kernel ~44.6–45.8% полного вызова, dest_alloc_zero (calloc
  zero-fill 8.3 МБ destination) ~32.7–33.9%, staging ~13.7–14.4%, copy_out ~7.0–7.2%. Полный вызов
  в этом раннере ~27.2–27.9 мс — это Dart VM/JIT (`dart test`), не Flutter AOT release, поэтому
  абсолютное число не сравнимо напрямую с 43–44 мс из базового отчёта; сравнима именно доля
  каждого этапа и абсолютное время самого kernel-вызова (native код одинаковый в обоих случаях).
- Важная методологическая находка: первая версия раннера копировала байты Dart-циклом
  (`buffer[i] = ...`) вместо bulk `asTypedList`/`setAll`, как делает сама библиотека — это дало
  staging/copy_out в 5–45 раз медленнее реального пути и было отклонено до публикации; финальная
  версия использует те же bulk typed-list операции, что `_allocateConstFrame`/
  `_copyDestinationPlanes` в `lib/src/yuv/impl/io/abi/yuv_abi_v1_runner.dart`.
- Pixel 3 720×360 **не измерен** — в этой сессии нет доступа к Android-устройству или
  Mac-runner мосту из другого проекта. Числа не выдуманы; замер остаётся открытым для исполнителя
  с доступом к Pixel 3, той же методикой (`yuv_convert_v1_bgra_stages_test.dart`, минимальная
  правка — вынести `_width`/`_height` в конфигурацию раннера или отдельный тест-файл).
- Рекомендация по порядку: BGRA-01/BGRA-02 (native kernel, ~45% полного вызова, единственный этап
  с уже известной конкретной неэффективностью — dispatch формата внутри пикселя цикла) первыми;
  BGRA-03 (destination zero-fill, ~33%, подтверждено измерением как throwaway работа для
  full-frame конверсии) — значим и должен идти по значимости перед BGRA-04, а не просто по
  номеру карточки; BGRA-04 (copy-out, ~7% на этом tight/unpadded входе после уже принятого OPT-14)
  — наименее значим на этом входе, но задачу стоит выполнить изолированно на padded/ROI входах
  прежде чем закрывать отрицательным выводом.
- Проверено: `dart analyze test/yuv_convert_v1_bgra_stages_test.dart` — чисто;
  `dart format --line-length 150` применён; `dart test` — 2/2 passed, checksum совпадает на каждом
  из 3 раундов. `flutter analyze`/`flutter test` не запускались — задача не трогает `lib/` и
  `speed_00_dart_ffi` не зависит от Flutter.

#### Review

**ACCEPT — T1 · GPT-6 Sol.** Раннер построчно сверен с `YuvAbiV1Runner._run`
(`lib/src/yuv/impl/io/abi/yuv_abi_v1_runner.dart`): staging использует тот же
`asTypedList(...).setAll(...)`, что `_allocateConstFrame`, destination —
`calloc`-zeroed без seed для full-frame конверсии, копирование результата — тот
же `Uint8List.fromList(...asTypedList...)`, что `_copyDestinationPlanes`.
`git diff 3564f5f HEAD -- src/yuv/` дал 0 строк — native C действительно не
менялся. Oracle-формула и порядок каналов в новом тесте идентичны уже принятому
`yuv_convert_v1_test.dart` (те же коэффициенты BT.601, тот же FNV-1a checksum),
а не новый непроверенный эталон; каждый из 30 прогонов на пару сверяется с
oracle внутри цикла, а не один раз. Все медианы, min/max и доли в отчёте
пересчитаны построчно из raw CSV и совпадают точно (округление до второго
знака). Оговорка Dart VM/JIT vs Flutter AOT (`~27–28 мс` в раннере против
`43–44 мс` в AOT-отчёте) корректна и не скрыта; сверена с фактическими числами
`conversion_windows_1080p_2026-09-26.md` (43.30–44.10 / 44.15–44.23 мс).
Pixel 3 честно отмечен как не измеренный, без выдуманных цифр. Working tree
чист, диапазон правки в этом коммите — только флип статуса и секция Executor
Report в todo.md плюс три новых файла отчёта/CSV/теста; более ранняя
реструктуризация шапки todo.md принадлежит предыдущему коммиту, не этому.
Рекомендация по порядку (BGRA-01/02 > BGRA-03 > BGRA-04) прямо следует из
измеренных долей (~45% kernel, ~33% dest_alloc_zero, ~14% staging, ~7%
copy_out). Ограничение проверки: в этой среде не удалось пересобрать
`yuv_ffi.dll` (`cmake` не найден в PATH), поэтому SHA-256 самой DLL не
воспроизведён напрямую -- принято на основании независимо проверяемого факта
отсутствия diff в `src/yuv/` между базовым замером и HEAD, а не на слово
исполнителя.

### BGRA-01 — NV12-ветка `yuv_convert_to_bgra`

**Статус:** DONE — реализовано по одобренному Architect Decision, коммиты `8d5a1fb` (тесты) и `0f29bc9` (правка). Принято T1-review.
**Исполнитель:** T2 · GPT-5.6 Terra; проверка — T1 · GPT-6 Sol.
**Зависит от:** BGRA-00 (принят, `d7e6a89`; kernel ~45% полного вызова, 12,11 мс NV12 на 1080p).
**Порядок:** выполняется первой. BGRA-02 стартует только после приёмки BGRA-01 и его отдельного коммита.

#### Architect Decision

Причина медленности, установленная по коду `src/yuv/abi/yuv_convert_v1.c` (стр. 78–118): внутри пиксельного цикла на каждый пиксель проверяются `packed` и `source->format`, а stride читаются через `source->planes[k].pixelStride` / `destination->planes[0].pixelStride`. Запись `to[0..3]` идёт через `uint8_t *`, которая по правилам C может алиасить любые объекты, поэтому компилятор обязан перечитывать поля view-структур после каждого записанного байта и не может ни вынести проверки, ни векторизовать цикл. Legacy `0.2.4` (`src/yuv/nv21/nv21_to_bgra8888.c`) использует ту же попиксельную формулу без особых приёмов; быстрее он был за счёт отсутствия dispatch внутри цикла, `int`-индексации и tight destination. Он служит ориентиром, но не oracle; его NV21-порядок каналов не переносить.

**Тир:** T2-исполнитель с T1-review подтверждён. Правка локальна (одна static-функция, без новых аллокаций и без изменения ABI), но затрагивает точную целочисленную арифметику, выбор fast/generic пути по stride и тонкости C: алиасинг `uint8_t *`, shift отрицательных `int32_t`, хвосты нечётной геометрии. Эти места должен независимо проверить T1. Повышать исполнителя до T1 не требуется: численный алгоритм не меняется, только порядок обхода.

1. **Dispatch один раз.** В начале `yuv_convert_to_bgra` для `source->format == YUV_VIEW_FORMAT_NV12` вызывать новую локальную `static void yuv_convert_nv12_to_bgra(source, destination)` и возвращаться. Packed- и I420-ветки остаются в существующем цикле без изменений (I420 — задача BGRA-02). `yuv_convert_v1` и его порядок validation/dispatch (стр. 182–230) не меняются.
2. **Инварианты в локальные `const`.** До цикла скопировать `width`, `height`, `yPs = planes[0].pixelStride`, `uvPs = planes[1].pixelStride`, `dstPs = destination->planes[0].pixelStride`. Строковые указатели считать один раз на строку через существующие `yuv_convert_const_at`/`yuv_convert_mutable_at` (они уже учитывают `rowStride` и row padding). Chroma-строка — `y / 2u`, как сейчас.
3. **UV один раз на пару Y.** Цикл по `x` с шагом 2. На пару читать `u = uv[0]`, `v = uv[1]` и считать chroma-слагаемые ровно в текущей целочисленной форме: `d = u - 128`, `e = v - 128`, `bTerm = 516 * d + 128`, `gTerm = -100 * d - 208 * e + 128`, `rTerm = 409 * e + 128`. Для каждого из двух Y: `c298 = 298 * ((int32_t)yy - 16)`, `B = clip((c298 + bTerm) >> 8)`, `G = clip((c298 + gTerm) >> 8)`, `R = clip((c298 + rTerm) >> 8)`, `A = 255`. Это та же сумма, что `(298*c + 516*d + 128) >> 8`: все операнды — `int32_t`, диапазон значений меньше ±150 000, переполнения нет, поэтому перестановка слагаемых даёт те же целые, а `>>` применяется к тем же значениям. При нечётной ширине последний пиксель строки обрабатывать отдельным хвостом с `cx = (width - 1) / 2`; этот chroma-сэмпл существует, так как ширина chroma равна `(width + 1) / 2`.
4. **Один общий `static inline` helper записи пикселя**, например `yuv_convert_store_bgra(uint8_t *to, int32_t c298, int32_t bTerm, int32_t gTerm, int32_t rTerm)`. Его вызывают и fast, и generic путь, поэтому формула существует в одном месте. `yuv_convert_clip` (стр. 68–76) сделать `static inline` без изменения логики (прецедент — `yuv_gaussian_blur_v1.c`). Запись 4 байт — по-байтово или через `uint8_t px[4]` + `memcpy(to, px, 4)`. Касты `*(uint32_t *)to` запрещены: это нарушение strict aliasing и невыровненная запись.
5. **Fast path и generic fallback выбираются один раз на кадр.** Fast path берётся при `yPs == 1 && uvPs == 2 && dstPs == 4`: pixel-tight, `rowStride` любой, то есть row padding тоже идёт по fast path. В нём индексы простые, указатели сдвигаются на `y += 2`, `uv += 2`, `to += 8` без умножения на stride — это даёт компилятору шанс автовекторизации. Generic путь — тот же цикл по парам, но смещения считаются как `(uint64_t)x * stride`, как сейчас, для любых допустимых `pixelStride` (gapped). Условие выбора пути нельзя расширять за пределы этих трёх равенств.
6. **Необязательный вариант B (2×2).** Обрабатывать две Y-строки на одну chroma-строку, чтобы chroma-слагаемые считались один раз на 4 пикселя, с хвостом при нечётной высоте. Реализовывать только после принятого варианта A (п. 1–5), мерить отдельно и оставлять только при воспроизводимом выигрыше kernel не меньше ~5% сверх A. Иначе записать как отрицательный результат.
7. **Вне рамок:** SIMD intrinsics, новые `.c`/`.h` файлы, флаги компиляции/CMake, `restrict`, lookup-таблицы, меняющие арифметику, многопоточность. Каждое из этого — отдельная карточка.

#### Constraints

- ABI v1 без изменений: структуры, `YuvStatus` коды, порядок validation (options header → reserved → frames → format pair), таблица `convertPairs`, отсутствие записей в destination при ошибке. Public headers (`h/yuv_ops_v1.h`, `h/yuv_abi_v1.h`) и generated `lib/src/functions/bindings/yuv_ffi_bingings.dart` не трогать; ffigen не перегенерировать.
- Формула BT.601 limited-range точная: коэффициенты 298/516/100/208/409, смещения −16/−128, `+128` и `>> 8` над `int32_t`, clip 0..255, B,G,R,A-порядок, `alpha = 255`. Никаких float, других коэффициентов, другого округления, fixed-point с иным масштабом. Разрешена только перестановка слагаемых из п. 3.
- Правка ограничена `yuv_convert_to_bgra`, новой `yuv_convert_nv12_to_bgra` и локальными `static inline` helpers в `yuv_convert_v1.c`. Не трогать `yuv_convert_copy*`, `yuv_convert_relayout`, `yuv_convert_from_packed`, packed RGBA→BGRA и I420-ветки, `yuv_kernel_v1.*`, `yuv_validate_v1.*`, `validated_view.*`, другие ABI-функции.
- Читать и писать только активные сэмплы: не трогать байты row padding и pixel gaps в destination, не читать за пределами `(planeWidth - 1) * pixelStride + sampleBytes` строки (гарантия validator'а). Нечётные width/height — без чтения несуществующего chroma.
- Существующие тесты и oracle не ослаблять. Legacy `0.2.4` — только алгоритмический референс.
- Изменения в `test_native/*.c` (новые кейсы тестов) входят в одобрение этого плана; production `.c` вне перечисленных функций — нет.

#### Definition of Done

- [x] Baseline до правки на HEAD `d7e6a89` (фактически `867355b`, native идентичен): собран Windows MSVC Release `yuv_ffi.dll`, SHA-256 записан. Kernel NV12→BGRA снят через stages-тест (2 раунда × 30) и `yuv_convert_v1_test.dart` (1281-wide, us/call и checksum).
- [x] Byte-exact native тест: `test_native/abi_convert_test.c` расширен независимым oracle для NV12→BGRA. Геометрии 1×1, 2×2, 1×9, 9×1, 7×5, 8×6, 33×17 × 7 layout'ов (tight, row-padded, pixel-gapped, mixed×2, unaligned×2) = 336 проверок. Crevices/canary и alpha проверены.
- [x] ROI: `YuvConvertOptionsV1` без ROI, подтверждено чтением кода; unaligned-data кейсы (+1 байт смещение `data`) покрывают ближайший практический аналог. Отдельного Dart ROI/crop-пути к `toBgra` не найдено.
- [x] Sanitizer: `abi_sanitizer_test.c` C-02b добавлен (9 кейсов pixel-gap/exact-length, чётные/нечётные, fast/generic/mixed). Прогнан ASan+UBSan на macOS Debug и Release **напрямую через clang с флагами CMakeLists.txt** (cmake недоступен ни на этом Mac, ни в Windows PATH — см. Executor Report), 190/190 проверок, exit 0. Windows `ctest` Debug+Release зелёный (11/11 целей).
- [x] Dart: `yuv_convert_v1_test.dart` (12 пар) и stages-тест — тот же checksum, 2 независимых раунда. `flutter test` пакета (6 файлов, 192+71 тестов) зелёный. Dart-файлы не редактировались, `dart format` неприменим. `git diff --check` чист.
- [x] Замер после правки: (a) kernel — stages-раннер и `yuv_convert_v1_test.dart`, см. таблицу в Executor Report; (b) полный вызов — full_call stages-раннера (Dart VM) и `tool/bench/dart` `CVT.NV12.BGRA` на Flutter AOT Release (баланс baseline `867355b` vs candidate `0f29bc9`, оба собраны как отдельные Windows-приложения). Выигрыш kernel (−34.7%) отдельно от выигрыша полного вызова (−20.8% AOT).
- [x] Регрессия соседей: I420→BGRA kernel/полный вызов без регрессии (в пределах шума), checksum идентичен; остальные 9 пар матрицы (включая RGBA→*) — checksum идентичен, время в пределах шума через `yuv_convert_v1_test.dart`.
- [x] Вариант B: не реализовывался (см. обоснование в Executor Report) — открытый пункт, не отрицательный результат по цифрам.
- [x] Отчёт: SHA DLL до/после, команды, числа, что взято из legacy — см. Executor Report. Два отдельных коммита (`8d5a1fb` тесты, `0f29bc9` правка). Pixel 3 720×360 — не измерено (нет доступа к устройству).

#### Executor Report

**Статус:** REVIEW
**Исполнитель:** T2 · GPT-5.6 Terra (Claude Sonnet 5)

Реализован ровно вариант A из Architect Decision (п. 1–5): `yuv_convert_to_bgra` теперь
проверяет `source->format == YUV_VIEW_FORMAT_NV12` один раз в начале и делегирует новой
`static void yuv_convert_nv12_to_bgra(...)`, которая возвращается сразу; packed- и
I420-ветки старого цикла не тронуты. `yuv_convert_clip` стала `static inline` без
изменения логики. Новый общий `static inline yuv_convert_store_bgra(to, c298, bTerm,
gTerm, rTerm)` пишет 4 байта побайтово (без `uint32_t`-каста) и вызывается и из fast,
и из generic пути — формула существует в одном месте. Fast path включается при
`yPs == 1 && uvPs == 2 && dstPs == 4` (row padding допускается на любом пути, т.к.
адресация всё равно идёт через `rowStride`); в нём указатели инкрементируются
(`y += 2, uv += 2, to += 8`) без умножения на stride. Generic fallback сохраняет прежнюю
адресацию `(uint64_t)x * pixelStride` для произвольных допустимых strides. UV читается
один раз на пару Y в обоих путях; нечётная ширина — хвостовой пиксель отдельно, с
`cx = (width - 1) / 2` (в fast-пути это тот же `uv`, на который успел сдвинуться цикл).
Вариант B (2×2 blocking) не реализовывался: выигрыш варианта A уже составил ~35% kernel,
дальнейшее уплотнение требовало отдельного раунда измерений, а Architect Decision явно
делает его опциональным и принимаемым только при доп. выигрыше ≥5% сверх A — с учётом
бюджета задачи и того, что I420-ветка (аналогичный кандидат для 2×2 из BGRA-02) ещё не
существует, решено не начинать вариант B в этой карточке. Отрицательный результат по
варианту B: **не пробовался**, зафиксировано как открытый пункт, не как отказ по цифрам.

**Baseline** (до правки, HEAD `867355b`, идентичен `d7e6a89` по `src/` — `git diff
d7e6a89 HEAD -- src/` дал 0 строк): Windows x64 MSVC Release, CMake `Visual Studio 17
2022`/x64. DLL SHA-256 `525FD04B4157E0B9CB95ED995E70D93F4B099C98EDFACD36B61CD23AF15D97F9`.

**Candidate** (после правки, коммит `0f29bc9`): тот же toolchain. DLL SHA-256
`A203D2A1BC2BF83D2BD726AEA55D5D4822E9C67D9C206D6C352519079E7A1467`.

Все измерения — 1920×1080 (stages-раннер, Dart VM) либо 1281×721 нечётной ширины
(`yuv_convert_v1_test.dart`), либо Flutter AOT release 1920×1080 (`tool/bench/dart`).

| Метрика | Baseline | Candidate | Выигрыш |
| --- | ---: | ---: | ---: |
| Kernel NV12→BGRA, стадийный раннер, медиана n=30 (1920×1080) | 12.1067 мс | 7.8877–7.9026 мс (2 раунда) | −4.20 мс, **−34.7%** |
| `yuv_convert_v1` NV12→BGRA, us/call (1281×721, нечётная ширина) | 5560.42 мкс | 3574.25–3587.22 мкс (2 раунда) | **−35.5…35.7%** |
| full_call стадийного раннера NV12→BGRA (Dart VM, не AOT) | 27.0284 мс | 22.8537–22.9377 мс | −4.09…4.17 мс, **−15.2…15.4%** |
| **Полный публичный вызов**, Flutter AOT Release, `tool/bench/dart` `CVT.NV12.BGRA` (n=30, медиана) | 43.1715 мс | 34.1730 мс | −8.998 мс, **−20.8%** |
| Kernel I420→BGRA (регрессия), стадийный раннер | 12.7276 мс | 12.9632–13.0336 мс | в пределах шума (BGRA-02 — отдельная карточка) |
| Полный вызов I420→BGRA, Flutter AOT `CVT.I420.BGRA` | 43.6120 мс | 43.5550 мс | без регрессии |

Checksum (FNV-1a в Dart-раннерах, SHA-256 в AOT bench) идентичен baseline и candidate
на каждой из проверок: стадийный раннер NV12→BGRA `0xbd2817acd7e16391`, I420→BGRA
`0x9fb2849898309858`; `yuv_convert_v1_test.dart` — все 12 пар без изменения ни одного
хэша (I420→I420 `0x939c3c5cf5e5a396` … RGBA→BGRA `0xdc396ecb1013c0a2`); AOT bench —
NV12→BGRA и I420→BGRA оба `b08cec9880b62a1957c53397509216d6c086ce56af2d1095840bc3d846cdc59f`
до и после. Regression-проверка остальных 10 пар матрицы (I420↔NV12, BGRA↔I420/NV12,
RGBA→I420/NV12/BGRA) — тот же список checksum, без изменений, времена в пределах шума.

**Byte-exact тест** (`test_native/abi_convert_test.c`, коммит `8d5a1fb`): новая функция
`test_nv12_to_bgra_geometry_and_layout` с независимым (не переиспользующим kernel) oracle,
геометрии 1×1, 2×2, 1×9, 9×1, 7×5, 8×6, 33×17 (более широкий диапазон, чем в задании,
стек-фикстура `Frame` ограничена 8×8 и фиксированным `pixelStride == sampleBytes`, поэтому
добавлена отдельная heap-фикстура `GapPlane` с произвольными `pixelStride`/`rowStride` и
опциональным `+1` смещением данных) × 7 layout'ов (tight/fast-path, row-padded,
pixel-gapped/generic, src-tight+dst-gapped, src-gapped+dst-tight, unaligned-tight,
unaligned-gapped) = 49 комбинаций, 336 проверок, включая alpha=255 и неизменность
canary в padding/gaps на всех трёх плоскостях. Данные Y/U/V включают экстремумы 0/255 в
углу кадра — clip проверяется с обеих сторон. Все 336 проверок пройдены на Windows
Debug и Release ctest, а также под ASan+UBSan на macOS (ниже).

**Sanitizer** (`test_native/abi_sanitizer_test.c`, коммит `8d5a1fb`, группа C-02b): 9
новых случаев NV12→BGRA с точными по размеру (`malloc` ровно на `rowStride*height`, без
запаса) аллокациями — fast-path чётный/нечётный/1×1, generic-path чётный/нечётный/1×1, и
три случая с гэпом только на одной из трёх плоскостей (Y/UV/dst). `cmake` недоступен ни в
PATH Windows, ни на Mac-runner (Homebrew установлен, но `cmake` не входит в его пакеты;
Android SDK на этом Mac отсутствует, в отличие от заметки для другого проекта) — поэтому
ASan/UBSan прогнаны через прямой вызов `clang` с теми же флагами, что
`test_native/CMakeLists.txt` задаёт для Linux/macOS non-MSVC цели
(`-fsanitize=address -fsanitize=undefined -Wall -Wextra -Werror -Wstrict-prototypes
-Wmissing-prototypes`), без cmake/ctest как таковых — сама сборка и её флаги не менялись,
изменился только способ вызова компилятора. LeakSanitizer не запрашивался отдельным
флагом на macOS (ASan на Darwin не поддерживает `detect_leaks`, как и описано в
комментарии `CMakeLists.txt`). Результаты на macOS 15.6.1 (arm64, Apple clang 17.0.0):
  - `abi_convert_test`: Debug (`-O0 -g`) и Release (`-O2 -DNDEBUG`) — оба `checks: 336,
    failures: 0`, exit 0, без сообщений ASan/UBSan.
  - `abi_sanitizer_test`: Debug и Release — оба `checks: 190, failures: 0, executed
    cases: 114` (включая 9 новых C-02b), exit 0, без сообщений ASan/UBSan. Группа
    allocation-failure injection пропущена как и раньше — `--wrap=malloc` требует
    GNU/gold/lld на ELF, недоступного на Darwin (см. существующий комментарий в файле);
    это не связано с BGRA-01 и не является новым пробелом.
  - Windows `ctest` (родная сборка через VS2022 cmake, `-DBUILD_TESTING=ON`): все 11
    целей зелёные и в Debug, и в Release, включая `abi_convert_tests` (336 проверок) и
    `abi_sanitizer_tests` (190 проверок).

**Dart:** `yuv_convert_v1_test.dart` (12 пар) и `yuv_convert_v1_bgra_stages_test.dart`
прошли с теми же checksum, что baseline, на двух независимых раундах. `flutter test` по
Windows-сборке пакета (не изолированный FFI-раннер, а сам `yuv_ffi` с native-библиотекой,
пересобранной из изменённого `src/`): `test/yuv_bgra_pixel_gap_test.dart`,
`test/conversions_test.dart`, `test/native_stride_safety_test.dart`,
`test/nv_chroma_order_test.dart`, `test/native_allocation_safety_test.dart`,
`test/reference_native_conversions_test.dart` — 192+71 тестов (частично пересекающиеся
прогоны), все зелёные. `dart analyze` на затронутых Dart-тестовых файлах (они не
менялись, только использовались для измерения) — чисто; Dart-файлы в этой задаче не
редактировались, только `src/yuv/abi/yuv_convert_v1.c` и два `test_native/*.c`, поэтому
`dart format` неприменим к правке. `git diff --check` — без ошибок (только штатные
предупреждения git о LF→CRLF).

**Из legacy `0.2.4` взято:** только диагноз "нет dispatch внутри цикла, простая
инкрементная адресация" как объяснение, почему исходный код был медленнее — ни код, ни
порядок каналов (`nv21_to_bgra8888.c` — NV21, а не NV12) не скопированы; формула и её
слагаемые не изменены относительно текущего `yuv_convert_v1.c`.

**Pixel 3 720×360:** не измерено — нет доступа к Android-устройству в этой сессии (то же
ограничение, что в BGRA-00). Остаётся открытым пунктом для исполнителя с доступом к
устройству, той же методикой co scaled-параметрами stages-раннера.

**Открытые пункты:**
1. Sanitizer прогнан без cmake/ctest (см. выше) — сами флаги и таргеты идентичны, но
   T1 может потребовать независимый прогон через фактический `ctest`, если найдёт cmake
   на другой машине или через `native-sanitizer-gate` CI job.
2. Вариант B (2×2 blocking) не реализовывался и не измерялся.
3. Pixel 3 720×360 не измерен.

#### Review

**ACCEPT — T1 · GPT-6 Sol.** Не поверила отчёту на слово: пересобрала native код на этой машине
(Windows, cmake из VS2022 Community, MSVC Release/Debug) и прогнала оба изменённых теста напрямую.

Что перепроверено самостоятельно (не по отчёту исполнителя):
- `git diff dcb336d HEAD -- lib/ h/` — 0 строк, public headers и generated bindings не тронуты.
- `git diff dcb336d HEAD --stat` — production-правка ограничена ровно `src/yuv/abi/yuv_convert_v1.c`
  (92 строки), плюс `test_native/abi_convert_test.c` и `abi_sanitizer_test.c`; никаких сторонних
  файлов не задето.
- `yuv_convert_v1.c` прочитан построчно: dispatch по `source->format == YUV_VIEW_FORMAT_NV12`
  срабатывает один раз на кадр перед циклом (не на пиксель), I420/packed-ветки байт в байт те же,
  что до правки, только с одним дополнительным branch на входе — это объясняет "I420 без регрессии"
  не только по цифрам исполнителя, но и по структуре кода. `yuv_convert_store_bgra` и
  `yuv_convert_clip` — `static inline`, без `uint32_t`-каста, побайтовая запись. Формула
  298/516/100/208/409, смещения −16/−128, `+128`, `>>8` не изменена — только перегруппирована
  (`c298 + bTerm/gTerm/rTerm` алгебраически равно `298*c + 516*d + 128` и т.д., переполнения нет).
- Арифметика хвоста нечётной ширины в fast-path проверена явным перебором (bash-симуляция
  инкрементов `uv`-указателя для width=1,3,5,7,9,33): позиция `uv` после цикла с шагом 2 всегда
  совпадает с `cx=(width-1)/2` — хвост читает правильный chroma-сэмпл, не сосед.
- Пересобрала `test_native` (cmake из
  `C:\Program Files\Microsoft Visual Studio\2022\Community\...\CMake\bin\cmake.exe` — на этой
  машине он в комплекте VS2022, хоть и не в PATH) и прогнала `abi_convert_test.exe` /
  `abi_sanitizer_test.exe` в Debug и Release напрямую (не по отчёту): оба дали ровно
  `checks: 336, failures: 0` и `checks: 190, failures: 0, executed cases: 114` — число в число как
  в Executor Report, без единого расхождения, exit 0 везде.
- Пересобрала эти же тесты на коммите `8d5a1fb^` (до добавления кейсов) для дифференциальной
  проверки: было `checks: 42` (convert) и `checks: 181, executed cases: 105` (sanitizer); дельта
  `+294` и `+9/+9` ровно соответствует 49 новым geometry×layout комбинациям (49×6 проверок каждая:
  status + oracle-match + alpha + 3×padding-intact) и 9 новым C-02b кейсам — числа не подогнаны,
  вывод получен независимым прогоном, а не пересчётом заявленного.
- Пересобрала главную `yuv_ffi.dll` из baseline (`867355b`) и из HEAD (`0f29bc9`) на этой машине;
  делегировала подагенту прогон `flutter test` (6 файлов, 192 теста) поочерёдно на обеих DLL через
  gitignored `yuv_ffi.dll` в корне (тот же механизм, что `test/reference_native_conversions_test.dart`
  использует сама) — оба прогона дали 192/192 passed, с идентичными per-plane sha256 на обеих
  сборках (не тавтология: сравнивались реальные хэши между двумя разными бинарями). Working tree
  подагент вернул чистым, посторонний pre-existing root DLL восстановлен.
- SHA-256 собранных на этой машине DLL (baseline `8312574C...`, candidate `DBF6CB08...`) не совпали
  с SHA из Executor Report (`525FD0...`/`A203D2...`) — это ожидаемо и не является дефектом:
  MSVC embeds timestamps/paths, идентичный SHA между разными машинами/сессиями не гарантирован даже
  при идентичном исходнике; сам факт другого SHA не опровергает отчёт, доказательство — поведение
  (checks/failures/checksum), а не байт-идентичность DLL, что и подтверждено выше независимо.

Принято на основании чтения кода/отчёта, без собственного пересчёта:
- ASan/UBSan прогон на macOS напрямую через `clang` с флагами `CMakeLists.txt`
  (`-fsanitize=address -fsanitize=undefined -Wall -Wextra -Werror -Wstrict-prototypes
  -Wmissing-prototypes`) — флаги проверены построчным сравнением с `test_native/CMakeLists.txt` и
  совпадают точно с тем, что реальный `ctest` использовал бы на Linux/macOS non-MSVC target. На этой
  Windows-машине `ctest` **не может** служить заменой: `CMakeLists.txt` явно отключает ASan/UBSan на
  MSVC (только компилирует и гоняет тесты без sanitizer-инструментации), так что "Windows ctest
  зелёный, 11/11" в DoD — правда, но не доказательство sanitizer-покрытия, только доказательство
  корректности логики тестов (что я и подтвердила прогоном выше). Открытый пункт №1 исполнителя
  (`sanitizer без cmake/ctest`) остаётся справедливым замечанием, но **не блокирует ACCEPT**: флаги
  идентичны, счётчики (336/190/114) сошлись число в число на независимом прогоне на другой машине,
  а обязательного `native-sanitizer-gate` CI job в проекте пока не существует, так что "повторный
  прогон через настоящий ctest" физически негде провести прямо сейчас без macOS/Linux машины с
  cmake. Рекомендация — не блокирующая: когда появится доступ к cmake на Mac/Linux или CI-джоба,
  повторить ASan/UBSan через реальный `ctest`, а не как условие приёмки этой карточки.
- Точные цифры производительности (kernel 12.11→7.89 мс stages-раннер, AOT full call
  43.17→34.17 мс) — не перемерены самостоятельно (для AOT `tool/bench/dart`/`tool/bench/native`
  требуют отдельной CMake-цели `yuv_bench.exe`, которой нет ни в одном из собранных на этой машине
  build-деревьев, и AOT-компиляция вне бюджета этой проверки). Направление и порядок величины
  правдоподобны: kernel ~35% быстрее при dispatch-вынесении из цикла и однократном UV-чтении на пару
  пикселей — некопирующая, чисто структурная оптимизация без изменения формулы, для которой такой
  выигрыш ожидаем и не выглядит завышенным.
- Вариант B (2×2) не реализовывался — соответствует Architect Decision: пункт явно опциональный
  ("Необязательный вариант B"), обязателен только количественный негативный вывод *если* вариант
  попробован и не дал ≥5% сверх A; полностью не начинать его — допустимое решение при заявленном
  бюджете задачи, не нарушение плана.

**Вывод:** BGRA-01 → DONE. Замечаний, блокирующих приёмку, не найдено. Единственная
рекомендация на будущее (не для этой карточки) — прогнать ASan/UBSan через настоящий `ctest`
на Mac/Linux, когда там появится cmake, и добавить native-sanitizer-gate в CI, чтобы такой ручной
обходной путь не повторялся из карточки в карточку.

### BGRA-02 — I420-ветка `yuv_convert_to_bgra`

**Статус:** TODO — Architect Decision готов; старт после одобрения плана пользователем **и** приёмки BGRA-01 (отдельный коммит).
**Исполнитель:** T2 · GPT-5.6 Terra; проверка — T1 · GPT-6 Sol.
**Зависит от:** BGRA-00; BGRA-01 (принятая структура NV12-пути и общий helper записи пикселя).

#### Architect Decision

Повторить принятую в BGRA-01 схему для I420. Legacy-референс `git show 0.2.4:src/yuv/yuv420/yuv420_to_bgra.c` содержит ту же формулу без дополнительных приёмов.

**Тир:** T2 подтверждён. Правка механически повторяет принятый образец; главный риск — перепутать независимые stride U/V или незаметно задеть общий helper. Оба риска ловятся тестами из DoD и T1-review.

1. В dispatch `yuv_convert_to_bgra` добавить ветку `YUV_VIEW_FORMAT_I420 → static void yuv_convert_i420_to_bgra(source, destination)`. После этого в исходном цикле остаётся только packed RGBA→BGRA. Разрешено удалить ставшие недостижимыми 4:2:0-ветки из этого цикла (стр. 84–86 и 95–115 текущего кода) только удалением; packed-операторы (стр. 89–94) остаются поведенчески идентичными.
2. Локальные `const`: `yPs`, `uPs = planes[1].pixelStride`, `vPs = planes[2].pixelStride`, `dstPs`, width/height. Указатели на строки U и V — один раз на строку, `y / 2u`.
3. Пара Y на один `(u, v)`: `u = uRow[cx * uPs]`, `v = vRow[cx * vPs]`, те же `bTerm/gTerm/rTerm` и **тот же** helper записи из BGRA-01, без копии формулы; хвост нечётной ширины — как в BGRA-01.
4. Fast path при `yPs == 1 && uPs == 1 && vPs == 1 && dstPs == 4`: указатели сдвигаются на `y += 2`, `u += 1`, `v += 1`, `to += 8`. Generic — через `(uint64_t)x * stride`. U и V в I420 — независимые планы с независимыми stride; условие fast path проверяет оба.
5. Вариант 2×2 — только если он был принят в BGRA-01, и с тем же порогом отдельного выигрыша.

#### Constraints

- Все ограничения BGRA-01 (ABI, формула, active-only доступ, вне рамок) действуют без изменений.
- **Общий helper записи/clip, принятый в BGRA-01, не менять.** Если изменение неизбежно, это повод остановиться и согласовать; в случае согласия NV12 полностью перепроверяется и перемеряется, как в DoD BGRA-01.
- Функцию `yuv_convert_nv12_to_bgra` не трогать. Packed RGBA→BGRA меняется только удалением недостижимого кода из п. 1.

#### Definition of Done

- [ ] Baseline I420→BGRA — на принятом коммите BGRA-01 (не на `d7e6a89`), та же сборка и тот же вход.
- [ ] `abi_convert_test.c`: те же геометрии и layouts, что для NV12, плюс I420-специфика — разные `pixelStride` у U и V (например, U `ps=1`, V `ps=3`), разные `rowStride` у U и V, смешанный случай «Y tight, chroma gapped». Существующий I420→BGRA 4×4 тест проходит без изменений. Крайние значения, alpha, canary.
- [ ] `abi_sanitizer_test.c` C-02: I420→BGRA с pixel gaps и exact-length аллокациями; полный `ctest` под ASan+UBSan на macOS/Linux (Debug + Release) и Windows `ctest`.
- [ ] **Регрессия NV12:** после правки повторить NV12→BGRA byte-exact тесты и kernel/full_call замеры BGRA-01. Время NV12 не хуже принятого в BGRA-01 в пределах шума, checksum тот же. RGBA→BGRA checksum и время тоже без изменений.
- [ ] Все 12 пар `yuv_convert_v1_test.dart` с прежними checksum; релевантные `flutter test`; format/analyze/diff-check.
- [ ] Замер I420: kernel (stages kernel + `yuv_convert_v1_test.dart`) и полный вызов (stages full_call + `tool/bench/dart` `CVT.I420.BGRA`), raw samples, медиана, разброс, выигрыш в мс.
- [ ] Отчёт, SHA DLL, отдельный коммит; T1-review принимает.

#### Executor Report

Ожидается после приёмки BGRA-01.

#### Review

Ожидает T1 · GPT-6 Sol.

## Позже

- [Предрелизные проверки Android, Windows, macOS, Web, Linux и iOS](doc/perf/prerelease-todo.md) выполняются после стабилизации конвертации на одном финальном SHA.
- Предыдущие задачи по blur, OPT-14 и остальным направлениям конвертации сохранены в [архиве](doc/perf/archive/todo-before-bgra-focus-2026-09-26.md); принятые результаты — в [COMPLETION.md](COMPLETION.md). Сейчас они не конкурируют с YUV→BGRA за активный цикл.
