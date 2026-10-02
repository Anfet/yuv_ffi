# PRESENT 1 — Режимы показа кадров в презентере
**Status:** ACCEPTED · **Tier:** T2 · **Owner:** — · **Depends On:** GEOM 1, SHADER 2, SHADER 3 · **Probe:** windows+pixel3

#### Goal
`YuvFramePresenter` / `YuvFrameView`: шейдерный путь, ориентация при рисовании, вписывание по `YuvFrameGeometry`.
Только добавления: без новых параметров всё работает как сейчас.

Пул этапа 4 «показ кадров»: GEOM 1 → SHADER 1 → SHADER 2 → SHADER 3 → PRESENT 1.

#### Architect Decision
1. **Презентер:**
   - `YuvFramePresenter({onFramePresented, bool useShader = false})`. `useShader: true` — кадры идут через
     `YuvFrameRenderer` (он сам решает, шейдер или BGRA). Кадры до окончания загрузки рендерера — обычным путём.
   - `present(YuvImage frame, {YuvFrameOrientation orientation = YuvFrameOrientation.upright})`; ориентация
     применяется при рисовании. «Один кадр в полёте», `reset`, `dispose`, `onFramePresented` — без изменений.
   - `image` при `useShader: true` — `null` (dartdoc говорит это прямо); при `false` — как сейчас.
2. **`YuvFrameView`** — новые необязательные `YuvFrameFit? fit`, `Alignment alignment = Alignment.center`,
   `ValueChanged<YuvFrameGeometry>? onGeometryChanged`.
   - `fit == null`, кадр `upright`, `useShader == false` — нынешнее дерево (`AspectRatio` + `RawImage`) без изменений.
   - Иначе виджет рисует кадр `YuvFrameRenderer.paint` по геометрии: при `fit == null` — внутри `AspectRatio` прямого
     кадра (`contain`), при заданном `fit` — на весь размер родителя.
   - `onGeometryChanged` — после кадра, когда геометрия изменилась (CAMERA 2 рисует по ней рамки и делает снимок).

#### Scope
- `lib/src/widgets/yuv_frame_presenter.dart`.
- `test/yuv_frame_presenter_test.dart`: старые тесты без правок; ориентация 90° меняет `AspectRatio`;
  `onGeometryChanged` вызывается один раз на изменение.
- `example/integration_test/presenter_shader_native_test.dart`: `YuvFrameView` с `useShader: true` в масштабе 1:1;
  `RepaintBoundary.toImage()` равен эталону решения 6 SHADER 2 (±1), I420 `upright` и «270° + зеркало».
- Замер: варианты `presenter_bgra` и `presenter_shader` в `example/lib/view04_draw_bench.dart`.
- `README.md` (абзац о `useShader` и ориентации), `CHANGELOG.md`.

#### Constraints
- Только добавления в API. Native, `lib/src/yuv/impl/**`, `tool/bench/` не трогать.
- Скорость — только release на Pixel 3 (`todo.md`, «Окружение → Windows»); экран включён, keyguard снят.

#### Definition of Done
- [x] API — по решениям 1–2; старые тесты презентера и example проходят (тестовый override расширен новым необязательным параметром).
- [ ] Новые тесты проходят на Windows и Android-эмуляторе; macOS и iOS Simulator postponed по решению Engineer.
- [x] Pixel 3 release, по два прогона: `presenter_shader` быстрее `presenter_bgra` на 720×480 и 1920×1080; медианы и
      сравнение с прототипом VIEW-04 (5,7–6,9 и 32,6–34,1 мс) — в отчёт. Если медленнее прототипа больше чем на 25 % —
      стадию, где теряется время, записать в отчёт; блокирует ли это приёмку, решает Reviewer.

#### Validation
Ключи: `lib/*` → `vm example`, `example/integration_test/*` → `all`.

- `dart format --line-length 150`; `flutter analyze` в корне и в `example/`.
- `pwsh -File tool/ci/vm.ps1`, `pwsh -File tool/ci/windows.ps1`, `pwsh -File tool/ci/example.ps1`,
  `pwsh -File tool/ci/android.ps1`; Mac: `bash tool/ci/macos.sh`, `bash tool/ci/ios.sh`.
- Pixel 3: замер из Scope.
- Probe `windows+pixel3`: Windows — в `tool/ci/windows.ps1`; Pixel 3 — Reviewer.

#### Executor Report
- Реализованы shader/BGRA режимы `YuvFramePresenter`, ориентация и геометрия `YuvFrameView`, сохранён точный legacy-путь без новых параметров.
- Добавлены widget-контракты геометрии и native pixel-parity integration для I420 `upright` и `rotation270 + mirror`.
- Pixel 3 release, экран включён, по два прогона (мс):

  | Размер | `presenter_bgra` | `presenter_shader` | VIEW-04 prototype |
  | --- | --- | --- | --- |
  | 720×480 | 32,804 / 32,790 | 16,503 / 16,471 | 5,7–6,9 |
  | 1920×1080 | 82,339 / 98,683 | 32,919 / 32,910 | 32,6–34,1 |

- Shader быстрее BGRA во всех прогонах. На 720×480 итоговый `present` → post-frame показатель больше прототипа более чем на 25%; тот же запуск показывает shader work около 6,1–6,5 мс, а потеря находится в ожидании draw-completion/vsync (итог около 16,3–16,5 мс), не в конвертации или upload. На 1920×1080 результат находится в диапазоне прототипа.
- Validation: `flutter test test/yuv_frame_presenter_test.dart` — 6/6; `tool/ci/vm.ps1` — 603/603; `tool/ci/windows.ps1` — PASS, включая 20/20 probe, 134/134 reference и оба shader integration; `tool/ci/android.ps1` — PASS на emulator-5554; `tool/ci/example.ps1` — PASS на Flutter 3.44.9.
- macOS/iOS validation: **postponed** по решению Engineer; зависимые карточки этим не блокируются, проверки будут повторены Engineer на Mac.

#### Review
Ревью 02.10.2026:
```text
Pool: STAGE4-VIEW; PRESENT 1
Outcome: ACCEPTED
Reviewed-Head: eaeb0ea
Merged-Head: none (слияние — вместе с пулом)
Fixed: none
Blocking: none
Advisory: замер present → post-frame квантуется vsync (16,5 мс — один кадр 60 Гц, 32,9 — два), поэтому прямое
  сравнение с прототипом VIEW-04 (время работы) некорректно — превышение >25 % на 720×480 не блокирует;
  в shader-пути исключение копирования уходит в FlutterError, а не бросается из present, как обещает dartdoc;
  example/test/present_camera_frame_test.dart правился ради новой сигнатуры present (неизбежно, файл удалён в CAMERA 2).
```
Legacy-дерево без новых параметров сохранено; тесты на AspectRatio и onGeometryChanged есть; macOS/iOS — postponed по
решению Engineer.
