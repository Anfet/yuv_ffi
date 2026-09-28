# Независимое ревью BGRA-00…05

Проверена ветка `release/0.4.2`, HEAD до ревью `a643b10`. Это ревью статусов по критериям в корневом `todo.md`; production C/Dart код не менялся. Итог: **0 COMPLETE, 6 TODO**. Наличие работающей Windows-оптимизации не оспаривается; статус TODO означает, что собственный критерий карточки ещё не закрыт.

## Что проверено независимо

- Пересчитаны группы из `bgra05_final_windows_1080p_raw.csv`: по три раунда для baseline/candidate и каждой пары, checksum внутри группы стабилен. Медиана медиан NV12→BGRA — 43,1865→30,0045 мс, I420→BGRA — 43,7135→30,5430 мс. Стенд `bench_abi_v1.dart` для этих двух пар вызывает **только `toBgraBytes()`**; `toBgra()` он вызывает лишь при исходном BGRA. Заголовок отчёта BGRA-05, перечисляющий оба публичных пути, шире фактически замеренного.
- Повторены адресные Flutter тесты `bgra03_dest_alloc_test.dart`, `bgra04_copy_out_test.dart`, `yuv_bgra_pixel_gap_test.dart`, `abi_status_mapping_test.dart`: 45/45. `conversions_test.dart` и `reference_native_conversions_test.dart`: 162/162. Эти зелёные тесты подтверждают проверенные сценарии, но не включают padded destination для `YuvAbiV1Runner.convert` после BGRA-03.
- `adb devices -l` сейчас видит Pixel 3 `8B1X11QLW` в состоянии `device`. В отчётах BGRA-00…05 Pixel 3 720×360 прямо указан как **не измеренный**. Наличие устройства сейчас не заменяет требуемый baseline/candidate прогон.
- В `.github/workflows/ci.yml` уже есть `native-sanitizer-gate`. Утверждение прежнего BGRA-01 review, что такой CI job отсутствует, ошибочно; ссылка на зелёный sanitizer run финального SHA в карточках не приведена. Ручные sanitizer-прогоны из прежних отчётов здесь не объявляются проваленными.

## Воспроизведённый дефект BGRA-03

`YuvAbiV1Runner.convert` принимает переданный вызывающей стороной `YuvAbiV1DestinationLayout`, но всегда задаёт `zeroFillDestination: false`. `_allocateMutableFrame` тогда использует `malloc`. Нативная конвертация записывает активные sample bytes, а `_copyDestinationPlanes` копирует **всю** длину плоскости, включая row/pixel padding. Утверждение в BGRA-03 Executor Report, что `convert()` всегда получает tight layout, неверно для прямого вызова этого метода.

Для проверки был запущен временный тест с реальным `yuv_convert_v1`: I420 2×2 → BGRA, destination `rowStride=12` при 8 активных байтах в строке. Тестовый `NativeAllocator.allocateUninitialized` выделял память и заполнял её `0xA5`, имитируя возможное содержимое `malloc`. Вернувшийся `YuvAbiV1FrameResult` сохранил `0xA5` в `[8..11]` и `[20..23]`. Тест прошёл, затем временный файл удалён; production-файлы не менялись. До BGRA-03 `calloc` давал в этих местах нули. Обычные публичные `toBgraBytes()`/`toBgra()` сейчас создают tight destination, поэтому этот дефект проявляется в общем runner при передаче padded/gapped layout, а не в измеренном tight 1080p сценарии.

Для принятия BGRA-03 требуется применять `malloc` только при доказанно плотных **всех** destination-плоскостях, иначе сохранять обнуление; добавить постоянную regression на padded и gapped layout, сравнить с прежним контрактом и повторить allocator-failure/atomicity тесты. Новый результат BGRA-05 после этой коррекции надо измерить повторно.

## Вердикт по карточкам

| ID | Текущее подтверждение | Невыполненный критерий |
| --- | --- | --- |
| BGRA-00 | Windows VM/JIT разбивка этапов и корректный checksum | Нет Pixel 3 720×360 и отдельного замера `toBgra()` в том же протоколе. |
| BGRA-01 | NV12 native ускорение и Windows AOT/контрактные результаты | Нет Pixel 3 720×360 baseline/candidate прогона; CI sanitizer на финальном SHA не указан. |
| BGRA-02 | I420 native ускорение и Windows AOT/контрактные результаты | Нет Pixel 3 720×360 baseline/candidate прогона и регрессионного NV12 замера на устройстве. |
| BGRA-03 | Для tight destination Windows выигрыш подтверждён | Padded/gapped destination публикует неинициализированный padding; Pixel 3 не измерен. |
| BGRA-04 | Отрицательный результат по изолированному copy-out в Windows Dart VM/JIT; production не менялся | Кандидаты не сверены по полному публичному AOT вызову и на Pixel 3, как задано в карточке/общих правилах. |
| BGRA-05 | Windows AOT `toBgraBytes()` ускорился приблизительно на 30%, checksum сохранился | BGRA-03 не принят; нет Pixel 3, отдельного `toBgra()` и измерения фактического пика памяти. |

Рабочий код остаётся в ветке для исправления и последующей приёмки. Статусы TODO не означают откат проверенного Windows ускорения.
