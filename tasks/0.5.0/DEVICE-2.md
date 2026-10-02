# DEVICE 2 — Прогон на Pixel 3, разбор и удаление прототипа VIEW-04
**Status:** REVIEW · **Tier:** T2 · **Owner:** DEVICE 1 · **Depends On:** DEVICE 1 · **Probe:** none

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
```json
{
  "card": "DEVICE-1",
  "schema": 1,
  "build_mode": "release",
  "git_sha": "25a33e0",
  "os": "android",
  "camera": {
    "lens": "front",
    "sensor_orientation": 270,
    "preset": "medium"
  },
  "steps": [
    {
      "id": "portrait_idle",
      "skipped": false,
      "seconds": 15.0,
      "display_fps": 29.5,
      "shader": true,
      "rotation": 270,
      "mirrored": true,
      "frame": "720x480"
    },
    {
      "id": "portrait_heavy",
      "skipped": false,
      "seconds": 15.0,
      "display_fps": 28.9,
      "shader": true,
      "rotation": 270,
      "mirrored": true,
      "frame": "720x480",
      "blur_runs": 13,
      "blur_ms_median": 441.4
    },
    {
      "id": "landscape",
      "skipped": false,
      "seconds": 15.0,
      "display_fps": 29.9,
      "shader": true,
      "rotation": 180,
      "mirrored": true,
      "frame": "720x480",
      "answer": true
    },
    {
      "id": "face_portrait",
      "skipped": false,
      "seconds": 15.0,
      "display_fps": 27.3,
      "shader": true,
      "rotation": 270,
      "mirrored": true,
      "frame": "720x480",
      "face_ratio": 1.0,
      "answer": true
    },
    {
      "id": "face_landscape",
      "skipped": false,
      "seconds": 15.0,
      "display_fps": 27.7,
      "shader": true,
      "rotation": 180,
      "mirrored": true,
      "frame": "720x480",
      "face_ratio": 0.9,
      "answer": true
    },
    {
      "id": "mirror",
      "skipped": false,
      "seconds": 0.0,
      "answer": true
    },
    {
      "id": "capture",
      "skipped": false,
      "seconds": 0.0,
      "capture": "720x138"
    }
  ],
  "notes": ""
}
```

| Проверка | Факт | Вердикт |
| --- | --- | --- |
| Сборка | release, `25a33e0` — SHA пула | PASS |
| Шейдер | `true` во всех пяти шагах с замером | PASS |
| Ориентация | portrait: 270 и mirror; landscape: 180 и mirror | PASS |
| FPS | 28,9 ≥ 0,9 × 29,5 = 26,55 | PASS |
| Обработка | 13 запусков за 15 с; медиана 441,4 мс | PASS |
| Лица | 1,0 и 0,9, оба ≥ 0,8 | PASS |
| Человек | `capture.answer` отсутствует, хотя шаг обязан спросить «Снимок совпадает с превью?» | FAIL |
| Полнота | пропусков нет | PASS |

Итог: **FAIL**. Числа превью выше прежнего VIEW-04 (20,4–21,1 FPS из 30): idle 29,5, с обработкой 28,9;
прототип VIEW-04 не удалён. Отсутствие `capture.answer` противоречит нормативной схеме DEVICE 1 и не доказывает
подтверждение «снимок = видимое». В DEVICE 1 это требует отдельной карточки исправления или решения Engineer;
текущая карточка завершена в REVIEW согласно решению 3.

#### Review
