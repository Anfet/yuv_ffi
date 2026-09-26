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
| BGRA-01 | TODO | BGRA-00: C значим | T2 · GPT-5.6 Terra; T1 · GPT-6 Sol | Оптимизировать только NV12-ветку `yuv_convert_to_bgra` в `src/yuv/abi/yuv_convert_v1.c`: вынести выбор формата из цикла, переиспользовать UV для пары Y, добавить быстрый tight путь при сохранении generic stride пути. Сравнить C и полный вызов; byte-exact, odd/padded/gapped и sanitizer проверки обязательны. |
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

**Статус:** TODO — Architect Decision готов; native C правится только после одобрения этого плана пользователем (AGENTS.md, «Native C code»).
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

- [ ] Baseline до правки на HEAD `d7e6a89`: собрать Windows MSVC Release `yuv_ffi.dll` (cmake из VS2022, в PATH его может не быть) и записать SHA-256 DLL и исходников. Снять kernel NV12→BGRA через `speed_00_dart_ffi/test/yuv_convert_v1_bgra_stages_test.dart` (стадия kernel и full_call, 3 раунда × 30) и `yuv_convert_v1_test.dart` (1281-wide, нечётная ширина, us/call и checksum).
- [ ] Byte-exact native тест: расширить `test_native/abi_convert_test.c` проверкой NV12→BGRA против независимого oracle, записанного в тест (формула попиксельно, без переиспользования кода ядра). Геометрии: 1×1, 2×2, 1×N, N×1, 7×5, 8×6, 33×17. Layouts: tight; row-padded; pixel-gapped (Y `ps=2`, UV `ps=3`, dst `ps=5`); смешанные (source tight / dest gapped и наоборот — проверяют выбор fast/generic пути); невыровненный `data` (+1 байт). Данные включают крайние Y=0/255 и U,V=0/255, чтобы задеть clip с обеих сторон. Проверяется alpha=255 и неизменность canary в padding/gaps.
- [ ] ROI в `yuv_convert_v1` нет (`YuvConvertOptionsV1` содержит только `reserved[3]`). Вместо ROI проверяется frame-view, начинающийся со смещения внутри большего буфера (ненулевой offset `data`, row padding). Если исполнитель найдёт Dart-путь, где `toBgra` вызывается на ROI/crop view, покрыть и его.
- [ ] Sanitizer: добавить в `test_native/abi_sanitizer_test.c` (C-02) NV12→BGRA кейсы с pixel gaps и exact-length аллокациями для нечётных и чётных размеров. Прогнать весь `ctest` с ASan+UBSan: на Windows sanitizers отключены (`test_native/CMakeLists.txt`), поэтому прогон на macOS через mac-runner (cmake из Android SDK, `-DBUILD_TESTING=ON`, Debug и Release) или Linux-job `native-sanitizer-gate` из `.github/workflows/ci.yml`. Приложить вывод с числом executed cases. Windows `ctest` (Debug + Release) тоже зелёный.
- [ ] Dart: `yuv_convert_v1_test.dart` и stages-тест проходят с **тем же checksum**, что до правки, для всех 12 пар (не только NV12→BGRA); релевантные `flutter test` пакета (`toBgra`/`toBgraBytes`, конвертация) зелёные; `dart format --line-length 150`/analyze для затронутых Dart тестов; `git diff --check`.
- [ ] Замер после правки — на той же машине, в той же сборке и с тем же входом: (a) C kernel — стадия kernel stages-раннера + `yuv_convert_v1_test.dart`; (b) полный вызов — full_call stages-раннера и Flutter AOT harness `tool/bench/dart` (сценарий `CVT.NV12.BGRA`, как в `conversion_windows_1080p_2026-09-26.md`). Raw samples, медиана, min/max, абсолютный выигрыш в мс и доля от полного вызова. Выигрыш kernel не выдаётся за выигрыш полного вызова.
- [ ] Регрессия соседей: I420→BGRA и RGBA→BGRA kernel не медленнее baseline (в пределах шума), checksum совпадает.
- [ ] Вариант B (если пробовался): отдельные числа A и A+B, решение принять/отклонить.
- [ ] Отчёт: SHA DLL до/после, команды, числа, что взято из legacy и что нет. Отдельный коммит; T1-review принимает. Pixel 3 720×360 — если доступен Android; иначе явно «не измерено».

#### Executor Report

Ожидается после одобрения плана и реализации.

#### Review

Ожидает T1 · GPT-6 Sol.

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
