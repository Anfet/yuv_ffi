# DEVICE 1 — Экран проверки на устройстве в example
**Status:** TODO · **Tier:** T2 · **Owner:** — · **Depends On:** CAMERA 2 · **Probe:** none

#### Goal
Этап 5 проверяет на настоящем телефоне то, что не видят CI и интеграционные тесты: FPS живого превью в release, в том
числе при тяжёлой обработке раз в секунду; поворот и зеркало; рамки лиц; «снимок = видимое». Интеграционный тест для
этого не подходит: `flutter drive` на мобильных работает только в debug/profile, а profile завышает стоимость FFI в
3–8 раз (`doc/perf-findings.md`); к тому же тест не попросит человека повернуть телефон.

Поэтому — экран проверки в example. Engineer запускает `flutter run --release`, проходит шаги на телефоне и
копирует итоговый JSON; разбор — DEVICE 2. Экран остаётся в example для этапа 6 и других устройств.

Пул этапа 5: DEVICE 1 → DEVICE 2.

#### Architect Decision
1. **Файлы** — `example/lib/device_check/`: `device_check_screen.dart` (экран и шаги), `device_check_report.dart`
   (сбор чисел и JSON, без Flutter-виджетов — чтобы тестировать отдельно). Вход: кнопка «Device check»
   (`Icons.fact_check`) в `AppBar` главного экрана `main.dart` и отдельная точка входа
   `example/lib/device_check_main.dart` (`runApp` сразу с экраном) — для запуска без касаний:
   `flutter run --release -t lib/device_check_main.dart`.
2. **Превью** — `YuvCameraView` (CAMERA 2) с фронтальной камерой, `ResolutionPreset.medium`, `fps: 30`, как
   `CameraScreen`; `onFramePresented` даёт FPS показа и `shader`, `onFrame` — ML Kit и тяжёлую обработку.
   Тяжёлая обработка — та же, что у `CameraScreen`: `_blurBgra` через `compute()` переносится в
   `example/lib/camera/heavy_blur.dart` (публичная функция, правило импортов папки CAMERA 1 соблюдено) и
   используется обоими экранами. ML Kit — как в `CameraScreen` (сырой кадр + `orientation.rotation`); рамка —
   `FaceRectPainter` в `overlayBuilder`.
3. **Шаги** — по порядку, у каждого: текст инструкции, кнопки «Старт», «Пропустить»; замер идёт 15 с от «Старт»,
   затем, где нужен глаз человека, — вопрос с кнопками «Да» / «Нет». Обработка включена только на шаге 2.
   | `id` | Инструкция | Сам считает | Вопрос |
   | --- | --- | --- | --- |
   | `portrait_idle` | Держите телефон вертикально | FPS показа | — |
   | `portrait_heavy` | Так же; включена обработка раз в секунду | FPS показа, число размытий, медиана мс размытия | — |
   | `landscape` | Поверните телефон горизонтально | FPS показа | «Превью повёрнуто верно?» |
   | `face_portrait` | Вертикально, лицо в кадре | доля кадров ML Kit с лицом | «Рамка на лице?» |
   | `face_landscape` | Горизонтально, лицо в кадре | доля кадров ML Kit с лицом | «Рамка на лице?» |
   | `mirror` | Поднимите правую руку | — | «Рука справа на экране?» |
   | `capture` | Нажмите «Снимок» | размер снимка | «Снимок совпадает с превью?» (снимок рядом с кадром превью, замершим в момент нажатия — `RepaintBoundary.toImage`) |
   Каждый шаг с замером дополнительно записывает `shader`, ориентацию кадра (`rotation`, `mirrored`) и его размер.
   FPS показа — число вызовов `onFramePresented` за окно замера, делённое на его длительность.
4. **Итог** — экран с JSON (моноширинный, прокрутка) и кнопкой «Копировать» (`Clipboard.setData`). Схема —
   нормативная, DEVICE 2 разбирает именно её:
   ```json
   {
     "card": "DEVICE-1", "schema": 1,
     "build_mode": "release", "git_sha": "abc1234", "os": "<Platform.operatingSystemVersion>",
     "camera": {"lens": "front", "sensor_orientation": 270, "preset": "medium"},
     "steps": [
       {"id": "portrait_idle", "skipped": false, "seconds": 15.0, "display_fps": 29.8, "shader": true,
        "rotation": 270, "mirrored": true, "frame": "720x480"},
       {"id": "portrait_heavy", "...": "...", "blur_runs": 14, "blur_ms_median": 230},
       {"id": "face_portrait", "...": "...", "face_ratio": 0.93, "answer": true},
       {"id": "capture", "skipped": false, "capture": "480x720", "answer": true}
     ],
     "notes": ""
   }
   ```
   `build_mode` — `release`/`profile`/`debug` по `kReleaseMode`/`kProfileMode`; не release — жёлтая плашка на
   экране шагов. `git_sha` — из `--dart-define=GIT_SHA=...`, по умолчанию `unknown`. `notes` — необязательное
   текстовое поле на экране итога. Числа округляются до 0,1.
5. **Логи для проверки без касаний.** При старте камеры — строка `DEVICE-1 ready {"build_mode":...,"shader":...}`
   после первого показанного кадра; после каждого шага — `DEVICE-1 step {json шага}`; в конце — `DEVICE-1 result
   {json}`. Вывод — `debugPrint`, как у стендов `view04_*` (в release он попадает в logcat; логгера в example нет).

#### Scope
- Создать `example/lib/device_check/{device_check_screen.dart, device_check_report.dart}`,
  `example/lib/device_check_main.dart`, `example/lib/camera/heavy_blur.dart`.
- `example/lib/main.dart` (кнопка входа), `example/lib/camera_screen.dart` (размытие — через `heavy_blur.dart`).
- Тесты `example/test/device_check/`: отчёт — FPS по окну, медиана, округление, `skipped`, схема JSON (ключи и типы
  решения 4); экран — на `support/fake_camera.dart`: «Пропустить» проходит все шаги до итога, «Копировать» кладёт в
  буфер тот же JSON, шаг с вопросом записывает ответ.
- `example/README.md` — раздел «Device check»: команда запуска с `GIT_SHA`, условия (экран включён, keyguard снят,
  телефон на зарядке не обязателен), что прислать.

#### Constraints
- `lib/` и native не трогать; новых зависимостей не добавлять.
- Прототип VIEW-04 не трогать — его удаляет DEVICE 2 после прогона.
- Только Android и iOS: на остальных платформах кнопка входа скрыта — ML Kit там нет (`CameraScreen` по той же причине отключает детекцию лиц).

#### Definition of Done
- [ ] Экран, шаги и JSON — по решениям 1–5; `CameraScreen` ведёт себя как раньше.
- [ ] Тесты из Scope проходят; `example/test` целиком проходит.
- [ ] Pixel 3 release: `flutter run --release -d 8B1X11QLW -t lib/device_check_main.dart --dart-define=GIT_SHA=<sha>`
      (или сборка APK + `adb install`) — в `adb logcat` есть строка `DEVICE-1 ready` с `"build_mode":"release"` и
      `"shader":true`; строка — в отчёт. Шаги с касаниями Executor не проходит — это DEVICE 2.

#### Validation
Ключи: `example/*` → `example`. Ветка пула — `example/STAGE5-DEVICE`.

- `dart format --line-length 150`; `flutter analyze` в `example/`.
- `pwsh -File tool/ci/example.ps1`.
- Pixel 3 (`todo.md`, «Окружение»): запуск из DoD.

#### Executor Report
#### Review
