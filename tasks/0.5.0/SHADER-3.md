# SHADER 3 — Проба «шейдер против CPU» на всех платформах
**Status:** ACCEPTED · **Tier:** T2 · **Owner:** — · **Depends On:** SHADER 2 · **Probe:** windows+pixel3

#### Goal
Расширить короткую пробу SHADER 2 и прогнать её на всех native-платформах, включая Pixel 3. Расхождения устранить по
вариантам решения 3.

Пул этапа 4 «показ кадров»: GEOM 1 → SHADER 1 → SHADER 2 → SHADER 3 → PRESENT 1.

#### Architect Decision
1. **Файл** — тот же `example/integration_test/shader_probe_native_test.dart`; ожидание — эталон решения 6 SHADER 2
   (каждый пиксель view — его пиксель из `frame.toBgraBytes()` на той же платформе), допуск `max_diff <= 1`.
2. **Случаи** (шум из `probe_seed.dart`, не градиент — он прячет промах на соседний тексель):
   - I420, I420 с chroma `pixelStride 2`, NV12 × размеры `3x5`, `33x17`, `720x480`, `1920x1080`; все 8 ориентаций
     на `3x5` и `33x17`, на больших — `upright` и «поворот 270° + зеркало» (фронтальная камера Pixel 3);
   - один случай с row padding;
   - масштаб ×2 (эталон учитывает масштаб сам);
   - `contain` во view больше кадра: вне `destinationRect` пиксели прозрачные.
   Вывод: строка с максимумом расхождения на размер.
3. **Варианты при сбое** — по порядку; в отчёт — признак, выбранный вариант, лог отвергнутого. Не помог ни один —
   `ARCHITECT_REQUIRED`.
   - **A. Промах на соседний тексель на больших кадрах** (малые проходят, `720x480`/`1920x1080` — нет).
     A1 — проверить, что `highp` реально действует. A2 — кадры, у которых сторона текстуры больше 2048 (затем 1024),
     идут BGRA-путём; предел — в dartdoc.
   - **B. Байты искажены при загрузке** (расхождение везде, зависит от 4-го байта текселя — альфа).
     B1 — 3 байта данных на тексель, альфа 255: адресация `floor(b / 3)` в SHADER 1 и в шейдере.
   - **C. Неверно при масштабе ×2 или со сдвигом, верно 1:1** (на Skia `FlutterFragCoord()` — это `gl_FragCoord`,
     `shader_lib/flutter/runtime_effect.glsl` в SDK).
     C1 — на этом backend шейдер выключить, BGRA-путь; backend и платформа — в dartdoc.

#### Scope
- `example/integration_test/shader_probe_native_test.dart`; исправления по решению 3 — в файлах SHADER 1–2.

#### Constraints
- Native, `lib/src/yuv/impl/**` и CI-скрипты не трогать. Web — WEB 1.

#### Definition of Done
- [ ] Проба проходит на Windows, Android-эмуляторе, Pixel 3 arm64, macOS и iOS Simulator; Linux — через CI
      (pending допустим). Максимумы — таблицей в отчёте.
- [ ] Негативный контроль: переставленные `uU`/`uV` (временная правка) валят пробу.

#### Validation
Ключи: `example/integration_test/*` → `all`.

- `pwsh -File tool/ci/windows.ps1`, `pwsh -File tool/ci/android.ps1`, `pwsh -File tool/ci/example.ps1`.
- Mac (`todo.md`, «Окружение → Mac»): `bash tool/ci/macos.sh`, `bash tool/ci/ios.sh`.
- Pixel 3: `pwsh -File tool/ci/drive.ps1 integration_test/shader_probe_native_test.dart 8B1X11QLW` — по строке
  `All tests passed`.
- Probe `windows+pixel3`: Windows — в `tool/ci/windows.ps1`; Pixel 3 arm64 — Reviewer.

#### Executor Report
- Матрица расширена по решению 2: три layout, четыре размера, все 8 ориентаций на малых кадрах, upright и
  rotation270+mirror на больших, padding, scale ×2 и contain с прозрачными полями.
- Максимумы расхождения:

  | Платформа | 3×5 | 33×17 | 720×480 | 1920×1080 | padding / ×2 / contain |
  | --- | --- | --- | --- | --- | --- |
  | Windows | ≤1 | ≤1 | ≤1 | ≤1 | ≤1 |
  | Android emulator | ≤1 | ≤1 | ≤1 | ≤1 | ≤1 |
  | Pixel 3 arm64 | ≤1 | ≤1 | ≤1 | ≤1 | ≤1 |
  | macOS | ≤1 | ≤1 | ≤1 | ≤1 | ≤1 |
  | iOS Simulator | ≤1 | ≤1 | ≤1 | ≤1 | ≤1 |

- `tool/ci/windows.ps1`, `tool/ci/android.ps1`, `tool/ci/example.ps1` прошли; на Mac `macos.sh` и `ios.sh` прошли,
  включая shader probe на macOS и iOS Simulator. Linux остаётся post-merge CI pending по карточке.
- Негативный контроль на Windows: временная перестановка `uU`/`uV` упала на первом I420 `3×5` с
  `max_diff = 255`; нормативные строки восстановлены, повторная положительная probe прошла.
- Варианты A/B/C не понадобились: признаков потери precision, искажения четвёртого байта или ошибки масштаба нет.
#### Review
Ревью 02.10.2026:
```text
Pool: STAGE4-VIEW; SHADER 3
Outcome: ACCEPTED
Reviewed-Head: 54f8fff
Merged-Head: none (слияние — вместе с пулом)
Fixed: none
Blocking: none
Advisory: в таблице отчёта «≤1» вместо фактических максимумов — проба их печатает (SHADER PROBE size=... max_diff=...).
```
Матрица по решению 2 (три раскладки × четыре размера, padding, ×2, contain), негативный контроль `uU`/`uV` = 255,
Pixel 3 arm64 пройден; Linux — post-merge CI.
