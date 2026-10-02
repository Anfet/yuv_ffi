# DEVICE 2 — Прогон на Pixel 3, разбор и удаление прототипа VIEW-04
**Status:** BLOCKED · **Tier:** T2 · **Owner:** DEVICE 1 · **Depends On:** DEVICE 1 · **Probe:** none

#### Goal
Engineer проходит экран проверки DEVICE 1 на Pixel 3 в release и присылает JSON. Исполнитель разбирает его по
критериям ниже, записывает вывод и, если проверка пройдена, удаляет прототип VIEW-04 — он больше не нужен.

Пул этапа 5: DEVICE 1 → DEVICE 2.

#### Architect Decision
1. **Прогон — Engineer.** `flutter run --release -d 8B1X11QLW -t lib/device_check_main.dart
   --dart-define=GIT_SHA=$(git rev-parse --short HEAD)` из `example/` на SHA ветки пула после DEVICE 1; экран включён,
   keyguard снят. JSON вставляется в раздел Executor Report этой карточки как есть (блок `json`).
2. **Критерии** — по схеме JSON DEVICE 1, решение 4:
   | Проверка | Условие PASS |
   | --- | --- |
   | Сборка | `build_mode == "release"`, `git_sha` — SHA ветки пула |
   | Шейдер | `shader == true` во всех шагах с замером |
   | Ориентация | `portrait_*`: `rotation == 270`, `mirrored == true` (фронтальная Pixel 3, CAMERA 1, решение 4); `landscape`/`face_landscape`: другой поворот, `mirrored == true` |
   | FPS | `portrait_heavy.display_fps >= 0.9 × portrait_idle.display_fps` |
   | Обработка | `portrait_heavy.blur_runs >= 12` за 15 с (раз в секунду, без зависаний) |
   | Лица | `face_portrait.face_ratio >= 0.8` и `face_landscape.face_ratio >= 0.8` |
   | Человек | `answer == true` во всех шагах с вопросом |
   | Полнота | ни один шаг не `skipped` |
   FPS сравнивается и с прежним путём (стенд VIEW-04: 20,4–21,1 из 30, `doc/view04-yuv-shader.md`) — только для
   записи, не критерий.
3. **Сбой.** Любая строка FAIL — в отчёт: шаг, числа, вероятная причина по коду; карточка → `REVIEW` с вердиктом
   FAIL, прототип не удаляется. Решение (починка — новая карточка, повтор или приёмка с оговоркой) — за Engineer.
4. **Вывод** — одна-две строки в `doc/perf-findings.md`: устройство, SHA, FPS без/с обработкой, медиана размытия,
   сравнение с VIEW-04.
5. **Удаление прототипа VIEW-04** (только при PASS; SHADER 2, решение 4; CAMERA 1, решение 3):
   `example/shaders/view04_i420.frag` и его строка в `flutter: shaders:` `example/pubspec.yaml`,
   `example/lib/view04_draw_bench.dart`, `view04_camera_bench.dart`, `view04_i420_shader.dart`.
   `CameraImageExt.toYuvImage` в `example/lib/ext.dart` удаляется, только если после этого у него нет пользователей в
   `example/lib/` и `example/integration_test/`; тесты, которые проверяют только его, удаляются вместе с ним, их список —
   в отчёт. Ссылки на удалённые файлы в `doc/` и `example/README.md` заменить ссылкой на коммит (`git show <sha>:<путь>`).

#### Scope
- Executor Report этой карточки (JSON и таблица критериев), `doc/perf-findings.md`.
- При PASS — удаление из решения 5 и правка ссылок.

#### Constraints
- `lib/` и native не трогать. Экран DEVICE 1 не менять; найденный в нём дефект — в отчёт.

#### Definition of Done
- [ ] JSON Engineer — в отчёте; таблица критериев решения 2 с фактическими значениями и вердиктом по каждой строке.
- [ ] Вывод — в `doc/perf-findings.md`.
- [ ] При PASS: прототип удалён; `flutter analyze` в `example/` чист, `example/test` проходит; поиск `view04` в
      `example/` пуст (кроме ссылок на коммит).

#### Validation
Ключи: `example/*` → `example`, `*.md`/`doc/*` → —. Ветка пула — `example/STAGE5-DEVICE`.

- `flutter analyze` в `example/`; `pwsh -File tool/ci/example.ps1` (после удаления).

#### Executor Report
#### Review
