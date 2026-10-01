# TEST 7 — Сверка эталона с libyuv
**Status:** ENGINEER_REQUIRED · **Tier:** T2 · **Owner:** — · **Depends On:** —

#### Goal
Эталон `test/reference/test_pattern_512` посчитан нашим же кодом на Dart
(`test/helpers/reference/test_pattern_reference.dart`). Если в нём ошибка, native, WASM и эталон могут ошибаться
одинаково, и ни один тест этого не увидит. Нужно один раз сверить эталон с независимой реализацией — libyuv — и
сделать сверку повторяемой. После этого TEST 5 может оставлять эталон единственным источником правды для
конвертаций и геометрии.

#### Architect Decision
- Инструмент `tool/oracle/`: `libyuv_harness.cc` и `check_reference.sh`. Скрипт клонирует libyuv на закреплённом
  коммите из [`doc/independent-oracles.md`](../../doc/independent-oracles.md) во временный каталог, собирает
  harness скалярными путями (команда из того же документа), прогоняет его по входам эталона и печатает таблицу
  расхождений. libyuv в репозиторий не копируется и зависимостью пакета не становится.
- Запуск — на Mac (там есть `clang++`): `bash tool/oracle/check_reference.sh`. На Windows не требуется.
- Сверяемые пары (вход → функция libyuv → наш артефакт):

  | Вход | libyuv | Артефакт |
  | --- | --- | --- |
  | `source_bgra8888.bin` | `ARGBToI420` | `source_i420.yuv` |
  | `source_i420.yuv` | `I420ToARGBMatrix` (`kYuvI601Constants`) | `i420_decoded.png` |
  | `source_i420.yuv` → NV21 | `I420ToNV21`, затем `NV21ToARGBMatrix` | `source_nv21_uv.yuv`, `nv21_uv_decoded.png` |
  | `source_i420.yuv` | `I420Rotate` 90/180/270 → `I420ToARGBMatrix` | `rotate_90.png`, `rotate_180.png`, `rotate_270.png` |
  | `source_i420.yuv` | `I420Mirror` → `I420ToARGBMatrix` | `flip_horizontal.png` |
  | `source_i420.yuv` | `I420Copy` с отрицательной высотой → `I420ToARGBMatrix` | `flip_vertical.png` |
  | `source_i420.yuv` | смещение указателей + `CopyPlane` → `I420ToARGBMatrix` | `crop_*.png` с чётным началом |

  Эффекты и blur libyuv не покрывает — они не сверяются.
- Критерий: по каналу Y и по каждому каналу BGRA печатаются максимум разницы и доля отличающихся пикселей.
  - Геометрия (поворот, зеркало, crop) — побайтно равна.
  - Y — разница не больше 1.
  - U/V и BGRA — любая разница больше 2 объясняется в Executor Report: разный алгоритм усреднения 2×2 или
    округления у libyuv (оговорки — в `doc/independent-oracles.md`) либо ошибка нашего эталона.
- Если найдена ошибка эталона — задача останавливается в `ENGINEER_REQUIRED` с описанием в карточке: исправление
  эталона меняет ожидаемые значения всех backend-ов, это решение Engineer.
- Итог сверки (SHA, коммит libyuv, таблица максимумов) дописывается разделом «Сверка эталона» в
  `doc/independent-oracles.md`; сырой вывод не коммитится.

#### Scope
- Ветка `task/TEST-7` от `dev`, worktree `.worktrees/TEST-7`.
- Новые файлы `tool/oracle/libyuv_harness.cc`, `tool/oracle/check_reference.sh`; строка `/tool/oracle/` в `.pubignore`.
- Раздел «Сверка эталона» в `doc/independent-oracles.md`; эта карточка.

#### Constraints
- `src/`, `lib/`, эталонные артефакты и генератор эталона не меняются.
- Скрипт не требует прав администратора и ничего не ставит глобально; каталог клона — во временном каталоге.
- Вывод скрипта — по `TEST GUIDELINES`: при успехе таблица максимумов и итог, при расхождении — пара, канал,
  координаты первого отличия, ожидаемое и фактическое.

#### Definition of Done
- [ ] `bash tool/oracle/check_reference.sh` на Mac проходит на чистом клоне `dev` и печатает таблицу по всем парам выше
- [ ] Геометрия совпадает побайтно, Y — в пределах 1; остальные расхождения объяснены в Executor Report
- [ ] Негативный контроль: при подмене `source_i420.yuv` испорченной копией (во временном каталоге) скрипт падает
      с ненулевым кодом и называет пару и канал
- [ ] Раздел «Сверка эталона» есть в `doc/independent-oracles.md`
- [ ] Пакет не изменился: `dart pub publish --dry-run` не показывает `tool/oracle/`

#### Validation
- Mac через mac-runner (окружение — «Окружение → Mac» в `todo.md`): синхронизировать ветку tar-ом,
  `bash tool/oracle/check_reference.sh`, затем негативный контроль.
- Windows: `dart pub publish --dry-run` в корне.

#### Executor Report

- Ветка `task/TEST-7`, HEAD `f738f7c` (`29a09b7`, `463b577`, `f738f7c`). Исправлены компиляция с закреплённым
  libyuv, где `CopyPlane` возвращает `void`, повторное имя NV21-буфера и line ending `check_reference.sh` при
  `git archive` на Windows. `.gitattributes` закрепляет для этого shell-скрипта LF; проверка извлечённого tar
  подтвердила отсутствие CRLF.
- Mac: SHA `f738f7c` синхронизирован в `~/claude-work/yuv_ffi-TEST-7-f738f7c` tar.gz по SSH. Обычный
  `bash tool/oracle/check_reference.sh` собрал harness и завершился с кодом 1. Прямые результаты согласованы:
  `bgra_to_i420` — Y max 0, U/V max 1; `i420_decode` и `nv21_decode` — B max 2, G/R max 1;
  `i420_to_nv21` и все raw Y/U/V для rotate, mirror и crop — max 0.
- Обычный прогон не проходит BGRA-сверку `rotate_90`, `rotate_180`, `rotate_270`, `flip_horizontal`,
  `flip_vertical` и `crop_inner`: B/R max 129, G max 91. Причина воспроизводима по генератору:
  `rotate_*`, `flip_*` и `crop_*` PNG строятся из `source` RGBA, а Architect Decision требует применить libyuv
  к `source_i420.yuv`. После 4:2:0 кодирования эти результаты не идентичны на цветных границах; это не допускаемое
  округление 1–2.
- Негативный контроль `ORACLE_CORRUPT_I420=1 bash tool/oracle/check_reference.sh` завершился с кодом 1 и назвал
  пару и канал: `bgra_to_i420`, Y, `(0, 0)`, expected 0, actual 16; также `i420_to_nv21`, Y, `(0, 0)`,
  expected 16, actual 0. То есть подмена временной копии обнаруживается. После этого ожидаемо остаются описанные
  выше несоответствия PNG geometry.
- Windows: `dart pub publish --dry-run` завершился успешно, `Package has 0 warnings and 1 hint`; в списке архива
  `tool/oracle/` отсутствует.
- **ENGINEER_REQUIRED.** Нужно утвердить эталон BGRA для геометрии после I420: рекомендую в harness сравнивать
  libyuv-результат с преобразованным `i420_decoded.png`, а текущие `rotate_*`, `flip_*`, `crop_*` оставить для
  RGB-операций. Альтернатива — изменить эти PNG на I420-пайплайн, что меняет общие эталонные артефакты и ожидаемые
  значения backend-ов. До решения нельзя выполнить критерий DoD о BGRA-сверке этих пар.
#### Review
