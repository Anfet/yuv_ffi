# TEST 7 — Сверка эталона с libyuv
**Status:** BLOCKED · **Tier:** T2 · **Owner:** — · **Depends On:** —

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

- Ветка `task/TEST-7`, HEAD `770fa18`; добавлены `tool/oracle/libyuv_harness.cc` и
  `tool/oracle/check_reference.sh`. Скрипт закрепляет libyuv на
  `2dd4257364d39c38d79465c4ddc4b93137fe729b`, собирает его только во временном каталоге и поддерживает
  негативный контроль через `ORACLE_CORRUPT_I420=1`.
- Harness сравнивает Y/U/V и BGRA, печатает максимум и долю различающихся пикселей, а при нарушении допуска —
  пару, канал, координаты и ожидаемое/фактическое значение. Для `NV21` U/V сопоставляются семантически, поскольку
  пакет хранит U,V, а libyuv `NV21` — V,U. Raw-операции rotate/mirror/crop также сверяются побайтно.
- Выполнено на Windows: `bash -n tool/oracle/check_reference.sh`, `git diff --check`,
  `dart pub publish --dry-run`. Windows-предохранитель скрипта подтверждён: без macOS `sips` он завершился с
  `FAILED: sips is required to decode PNG references.`
- **BLOCKED:** в этой сессии нет инструмента mac-runner, поэтому Mac-прогон, таблица фактических максимумов и
  негативный контроль не запускались. Для продолжения на Mac: `bash tool/oracle/check_reference.sh`, затем
  `ORACLE_CORRUPT_I420=1 bash tool/oracle/check_reference.sh`.
#### Review
