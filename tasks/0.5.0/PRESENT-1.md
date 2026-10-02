# PRESENT 1 — Режимы показа кадров в презентере
**Status:** BLOCKED · **Tier:** T2 · **Owner:** SHADER 3 · **Depends On:** GEOM 1, SHADER 2, SHADER 3 · **Probe:** windows+pixel3

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
  `RepaintBoundary.toImage()` равен `geometry.apply(frame).toBgraBytes()` (±1), I420 `upright` и «270° + зеркало».
- Замер: варианты `presenter_bgra` и `presenter_shader` в `example/lib/view04_draw_bench.dart`.
- `README.md` (абзац о `useShader` и ориентации), `CHANGELOG.md`.

#### Constraints
- Только добавления в API. Native, `lib/src/yuv/impl/**`, `tool/bench/` не трогать.
- Скорость — только release на Pixel 3 (`todo.md`, «Окружение → Windows»); экран включён, keyguard снят.

#### Definition of Done
- [ ] API — по решениям 1–2; старые тесты презентера и example проходят без правок.
- [ ] Новые тесты проходят на Windows, Android-эмуляторе, macOS, iOS Simulator.
- [ ] Pixel 3 release, по два прогона: `presenter_shader` быстрее `presenter_bgra` на 720×480 и 1920×1080; медианы и
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
#### Review
