# yuv_ffi 0.4.2 — ускорение native C по одной функции

| Готово | ID | Статус | Владелец | Зависит от | Кратко |
| --- | --- | --- | --- | --- | --- |
| [x] | C-11 | DONE | GPT-6 Sol · T1 | C-10 (`77223ae`) | Оптимизировать `yuv_gaussian_blur_v1`; затем повторить её Dart-тест |
| [ ] | OPT-13 | REJECTED | GPT-6 Sol · T1 | C-11 (`74a1496`) | Дополнить проверку full-ABI Gaussian и Dart allocator guarantees |
| [ ] | SPEED-12 | BLOCKED | GPT-5.6 Terra · T2 | C-01—C-11 | Свести результаты и выполнить нужные проверки корректности |

Цель — ускорить текущую реализацию 11 экспортируемых функций ABI v1, сохранив результат и контракт 0.4.1. Регрессию скорости относительно 0.2.4 принимаем как исходное наблюдение: старую версию здесь не замеряем, но **обязательно изучаем её C-код как источник быстрых алгоритмических приёмов**. Ориентир для каждой функции — ускорение порядка 10× относительно её собственного времени до правки. Работа идёт последовательно: **один Dart-тест функции → время текущей реализации → разбор быстрого legacy кода → правка C-функции → повтор того же теста → вывод**.

Прежняя декомпозиция PERF-01—38 и MEAS-01—03 сохранена [в архиве](doc/perf/archive/perf-matrix-todo-2026-09-25.md) как история уже сделанной работы и измерений. Её платформенная матрица, требования к Power Plan и готовые предложения алгоритмов больше не управляют этим планом. Старые отчёты не удалены и не объявлены новыми замерами.

**Исполнители по тирам:** T1 — GPT-6 Sol для сложного численного кода и общих ядер; T2 — GPT-5.6 Terra для локальных изменений с несколькими форматами и правилами ABI; T3 — GPT-6 Luna для узкой функции с готовым контрактом. Работу T3 проверяет Terra. Tier оценивает сложность функции и риски корректности, а не объём тестового файла.

Существующие `tool/bench/` и `doc/perf/` остаются справочным материалом. Для этой работы не нужен общий benchmark suite или отдельная карточка измерений на каждую функцию.

## По одной C-функции

В каждой строке ниже одна рабочая карточка и один адресный Dart-тест. Для функции проверяются допустимые форматы и параметры текущего ABI v1. Legacy исходники доступны по тегу `0.2.4`: I420 — `src/yuv/yuv420/`, прежний NV — `src/yuv/nv21/`, BGRA — `src/yuv/bgra8888/`. Их нужно прочитать, но старую библиотеку собирать и измерять не требуется.

| Готово | ID | Native C функция / основной файл | Сценарии одного теста | Исполнитель | Причина tier |
| --- | --- | --- | --- | --- | --- |
| [x] | C-11 | `yuv_gaussian_blur_v1` · `yuv_gaussian_blur_v1.c` | I420, NV12, BGRA; radius 1/3, sigma 1.0/1.5, full-frame/ROI | T1 · Sol | Точность двухмерного Gaussian oracle и ограниченный scratch |

### C-11 — Ускорить `yuv_gaussian_blur_v1`

**Статус:** DONE
**Исполнитель:** GPT-6 Sol · T1, high numerical reasoning
**Зависит от:** C-10 (принят, коммит `77223ae`)

#### Architect Decision

Добавить один адресный Windows Dart FFI тест `speed_00_dart_ffi/test/yuv_gaussian_blur_v1_test.dart`. Измерять radius 1/sigma 1.0 и radius 3/sigma 1.5 на I420/NV12/BGRA, full-frame и odd-boundary ROI, odd 4:2:0 geometry. Сначала снять Release baseline и прочитать legacy `0.2.4` Gaussian реализации. Оптимизировать только `yuv_gaussian_blur_v1.c`: сохранить заданную ABI v1 двухмерную Gaussian weight формулу и порядок weighted accumulation, вычислять неизменный нормализующий `total` один раз, а не для каждого pixel. Проверить простые функции clip/decode/read в горячих циклах на явное `static inline`/инлайнинг; макрос применять только при безопасных аргументах и измеримой выгоде. Не менять общий `yuv_kernel_v1_blur`, mean/box operations, ABI и соседей. Weight table и scratch allocation должны быть bounded/checked до первой destination write; не создавать full-frame scratch, растущий сверх принятого C-10 bounded-ring budget.

#### Constraints

Сохранить ABI v1, radius 0 behavior, reject radius >256, border clamp, конечную sigma >0, status/validation, alpha preservation, exact half-up rounding, 2D weighting, ROI shared-chroma semantics и error atomicity. Не менять ABI/shared helpers/box/mean functions. Все allocations и overflow checks до destination writes. Legacy — алгоритмический референс, не oracle; старую библиотеку не собирать/мерить. Исполнитель меняет native C сам в пределах карточки.

#### Definition of Done

- [ ] Один Dart FFI test покрывает I420/NV12/BGRA × radius 1/3 с зафиксированной sigma; full-frame/odd-boundary ROI; odd 4:2:0 geometry; radius 0, padded strides, invalid sigma (0, отрицательная, NaN/Infinity) и no writes.
- [ ] Каждый output byte совпадает с независимым Dart oracle для 2D Gaussian формулы; checksum и validation status проверены.
- [ ] Baseline/post timings для идентичных inputs/параметров; вызовы timed отдельно от fixture/oracle.
- [ ] Изучены legacy C реализации `0.2.4`; записано применённое/отклонённое ускорение с объяснением byte-exact ограничений.
- [ ] Windows Release test, format/analyze/diff-check и относящиеся native blur tests проходят; общий kernel, mean и box не изменены.
- [ ] Структурированный отчёт с DLL hashes, командами, timings/speedups и memory bound независимо проверен Terra.

#### Executor Report

Ожидается после реализации.

#### Review

Ожидает независимой проверки Terra.

Для каждой строки:

1. Прочитать ABI v1 функцию, вызываемые ею helpers и соответствующие C-реализации 0.2.4. Установить, какие различия в алгоритме и проходах по данным могли давать прежнюю скорость; не считать старую реализацию эталоном корректности. Написать адресный Dart-тест, проверить результат и снять время текущей сборки на Windows до правки.
2. Выбрать, что можно перенести из 0.2.4 с учётом ABI v1, либо предложить новый быстрый алгоритм. Исполнитель самостоятельно меняет native C в пределах назначенной функции и необходимых ей helpers, соблюдая контракт ABI v1. Если изменение общего helper затрагивает соседние операции, проверить и адресно перемерить их.
3. Изменить C-код, повторить **тот же** тест с теми же входами и параметрами, прогнать относящиеся к функции проверки корректности. Если затронут общий helper, отдельно проверить вызывающие его функции.
4. Оставить короткий вывод `до / после`: какой приём найден в 0.2.4, что перенесено или заменено, вход и параметры, времена, коэффициент ускорения, проверка результата и причина оставшегося узкого места. Если ускорение порядка 10× не достигнуто, проверить следующий вариант для той же функции либо указать, что именно ограничивает дальнейший выигрыш.

ABI v1 и его требования к валидации, ошибкам, stride/padding, ROI, цвету и атомарности записи сохраняются. Оптимизация не должна подменять проверку результата.

В ABI v1 нет отдельной native C функции «создать изображение»: конструкторы находятся на Dart-стороне. Если после ускорения C вызовов создание остаётся заметной частью времени, завести отдельную задачу по результату адресного профиля, не смешивая её с тестом native функции.

### OPT-13 — Проверить blur buffers и Dart plane copies

**Статус:** REJECTED
**Исполнитель:** GPT-6 Sol · T1; проверка заключения — GPT-5.6 Terra · T2
**Зависит от:** C-11 (принят, commit `74a1496`)

#### Architect Decision

Это отдельное исследование после завершения native blur функций. Не менять production source и не смягчать тестовые oracle, пока результаты не собраны и рассмотрены. Проверить четыре предложения: (1) размывать visible RGB один раз и переиспользовать значения для luma/chroma encode; сравнить full-frame RGB buffer с bounded row-buffer C-09/C-10; (2) проверить принятые integer separable box/mean rolling sums против точного 2D окна на всей выбранной radius/edge/ROI выборке; (3) сравнить separable Gaussian с ABI v1 2D double формулой, измерить speedup и распределение byte differences; (4) изучить реальные Dart destination allocation и plane-copy paths, сравнить `malloc`/`calloc` и row-copy при `pixelStride == sampleBytes`, только если можно сохранить padding и исключить использование неинициализированной памяти.

#### Constraints

OPT-13 не начинать до приёмки C-11. Текущие byte-oracle и ABI v1 остаются критерием. Для Gaussian измерить число/долю отличающихся bytes, max delta, координаты (border/interior/ROI/shared chroma) и проверить ±1 гипотезу; production C и тесты не ослаблять. Для Dart `malloc` отдельно учесть active bytes, row padding, error/no-write paths, zeroing contract и возможную выдачу неинициализированной памяти. Сравнивать те же inputs на Windows Dart tests и записать time/memory trade-offs. Допускаются временные prototypes в адресном test-пакете; production code не менять. Не менять C-09/C-10.

#### Definition of Done

- [ ] Найдены текущие Dart allocation и plane-copy call paths с точными файлами/функциями и перечнем bytes, которые обязаны быть initialized.
- [ ] Сравнены full RGB buffer и bounded row-buffer для blur: времена и peak scratch memory на идентичном workload.
- [ ] Integer separable box/mean проверены против byte-exact 2D oracle на форматах, границах, odd 4:2:0, ROI и радиусах.
- [ ] Gaussian 1D candidate сравнен с точным 2D oracle по скорости и разнице каждого output byte; дан вывод, совместимо ли ±1 с действующими ожиданиями. Любое изменение tolerance только предложить, не вносить.
- [ ] `malloc`/`calloc` и row-copy замерены на фактическом Dart пути; безопасность padding, validation failure и no-write cases подтверждена.
- [ ] Отчёт даёт рекомендацию по каждому пункту и предлагает узкие implementation tasks, если выигрыш доказан; production source не изменён.

#### Executor Report

- Box/mean уже используют integer separable rolling sums и повторное использование RGB результатов. Их текущие адресные тесты прошли 34/34 с ROI, borders, odd geometry, padded strides и большими радиусами; отдельная оптимизация этого алгоритма не нужна.
- Full-height RGB ring против bounded ring в одинаковых Clang Release вариантах не дал стабильной разницы на 321×241/r3: примерно 9.5–11.1 против 9.5–11.7 ms/call, лидер зависел от порядка. На 4000×3000/r3 память около 48 MB против 144,392 bytes у C-11. Оставить bounded ring.
- В packed BGRA 2D→1D prototype получил 3.4× при r3/321×241, 8.5× при r7/321×241 и 3.3× при r3/1920×1080. Dart separable prototype имел 0 byte diffs на 2,181,436 output bytes в 18 I420/NV12/BGRA full/ROI сценариях с r1/r3/r7 и нечётными размерами; дополнительные BGRA sigma 0.5/1/1.5/2.7/20 также дали 0 diffs. Выборка не доказывает универсальную byte equality: tolerance ±1 не вводить. Полноразмерный double intermediate потребует ~288 MB при 12 MP; оценка горизонтального ring при 4000/r256 — ~49 MB. Рекомендован временный ограниченный full-ABI прототип и тест расширенного oracle перед решением о production.
- Runner использует `calloc` для descriptors и plane buffers; ROI seed копирует active samples, success copy-back переносит полные plane lengths. Временный allocator `malloc` только для больших planes с calloc для малых descriptors дал те же hashes; 3.1–5.5 vs 3.8–5.5 ms/call без устойчивого выигрыша. Глобальную замену на malloc не рекомендовать из-за padding/uninitialized bytes. Row copy при `pixelStride == sampleBytes` дал ~600→6.4 µs на 321×241 и ~44→0.8–1.1 ms на 1920×1080 BGRA с теми же checksums; padded 7×5 BGRA сохранил padding. Предложить отдельный T2 task для `_seedPlaneFromSource` и `YuvAbiV1ImageTransport.applyTo`, скопировать только `planeWidth * sampleBytes` на строку.
- Окружение: Windows x64, Dart 3.12.2, Clang 16 `-O3`; C-11 DLL SHA-256 `4D89BDC2D41FE31DCD2DA2BBDEA6CB3AB6F8AC9F0DFC84B716A31B9D2207AA59`. Полные команды и caveats приведены в отчёте исполнителя; временные prototypes/DLL удалены, рабочее дерево не менялось. Gaussian full ABI 1D и `malloc` error/no-write cases требуют дополнительной проверки до любой production правки.

#### Review

**REJECT — GPT-5.6 Terra · T2.** C-09/C-10 integer rolling sums и scratch memory math подтверждены. Для `_seedPlaneFromSource` row-copy разрешён только если `source.pixelStride == sampleBytes` и `destination.pixelStride == sampleBytes`; `YuvAbiV1ImageTransport.applyTo` может копировать `planeWidth * sampleBytes` и сохранять row padding.

Не закрывать OPT-13, пока не будут выполнены следующие проверки:

1. Gaussian: сохранить воспроизводимый prototype/команды/raw timing и измерить полный native ABI 1D вариант на I420/NV12/BGRA, ROI/shared chroma, border, padded/non-contiguous stride, radius 0/256, sigma range, alpha, error atomicity и allocation failure. Отчёт включает byte-diff count/fraction/max delta/coordinate classes. До этого 1D остаётся кандидатом, ±1 tolerance не менять.
2. Dart allocator: проверить `NativeAllocator` zeroed-memory contract и пути validation failure/no-write/padding для `malloc`; не предлагать общий переход с calloc. Отдельный partial malloc production task не открывать без доказанной выгоды и полной инициализации.
3. Row-copy рекомендации сохранить как будущую узкую T2 карточку с требованием обоих tight pixel strides для seed copy и тестами pixel/row padding; не начинать implementation в рамках OPT-13.

## Завершение

**Исполнитель:** T1 · Sol — итоговая сверка корректности и результатов всех функций.

- [ ] После C-01—C-11 прогнать существующие проверки корректности изменённого кода и свести времена `до / после` по каждой функции. Платформенные и релизные проверки не входят в этот цикл рефакторинга.
