# WEB 1 — Шейдер `YuvFrameRenderer` на Web: проба и решение
**Status:** IN_PROGRESS · **Tier:** T2 · **Owner:** PAR-WEB · **Depends On:** SHADER 3 · **Probe:** windows

#### Goal
SHADER 2 (решение 1) требовала на Web до WEB 1 рендерер без шейдера, но выключателя нет: `YuvFrameRenderer.load()`
грузит `shaders/yuv_frame.frag` на любой платформе. На Web шейдер, вероятно, уже рисует I420/NV12 и ни разу не
сверялся с CPU. Камеру example это не задевает (Web-камера отдаёт BGRA, `YuvPlanesTexture.pack` → `null`), а
пользователя пакета, который показывает I420/NV12 на Web, — задевает. Задача: прогнать шейдерную пробу в Chrome и по
результату либо подтвердить шейдер на Web, либо выключить его.

Параллельная задача: этапы не блокирует. Пул `PAR-WEB`: WEB 1 → WEB 4.

#### Architect Decision
1. **Одни случаи для native и Web.** Тело `example/integration_test/shader_probe_native_test.dart` (матрица SHADER 3:
   раскладки × размеры × ориентации, padding, ×2, contain, строка `SHADER PROBE ...`) переносится в
   `example/integration_test/helpers/shader_probe_cases.dart` как
   `Future<Map<String, int>> runShaderProbeCases(YuvFrameRenderer renderer)` (возвращает максимумы по случаям и не
   делает `expect`). Native-файл вызывает её и проверяет, как сейчас; его поведение и вывод не меняются.
2. **Web-проба** — `example/integration_test/shader_probe_web_test.dart`: `YuvFfi.initialize()`,
   `YuvFrameRenderer.load()`, печать `SHADER PROBE web has_shader=<bool>`, затем по `hasShader` — `runShaderProbeCases`
   и печать максимумов. Запуск — `tool/ci/drive.ps1 integration_test/shader_probe_web_test.dart web-server
   --browser-name=chrome --headless` (renderer по умолчанию — CanvasKit; `--wasm` в задачу не входит).
3. **Решение по результату** (признак — в отчёт):
   - **A. `hasShader == true`, все случаи `max_diff <= 1`** → шейдер на Web остаётся; Web-проба проверяет
     `hasShader == true` и `max_diff <= 1`. README: одна фраза «на Web (CanvasKit) шейдер сверен с CPU».
   - **B. `hasShader == true`, есть расхождения** → в `load()` выключатель: `if (kIsWeb) return YuvFrameRenderer._(null);`
     с комментарием-причиной (случай и максимум). Web-проба проверяет `hasShader == false`. Расхождения — таблицей в
     отчёт; dartdoc `hasShader`: «на Web всегда `false`, причина — WEB 1».
   - **C. `hasShader == false` без выключателя** (шейдер на Web не загрузился) → выключатель не нужен; Web-проба
     проверяет `hasShader == false`; ошибку загрузки (`load()` её глотает — временно вывести в пробе через свой
     `FragmentProgram.fromAsset`) — в отчёт.
   В любом варианте Web-проба остаётся в репозитории и закрепляет выбранное поведение.
4. **Матрица `tool/ci/web.ps1`** (`Assert-WebSourceMatrix`): `shader_probe_web_test.dart` — в `$separate` и
   `$executionSources`, в `$baselineCases` — `1`; проверки «13 источников / 62 случая» → 14 / 63; итоговая строка
   `Web CI passed` — `sources=14; integration cases=63`.
5. **Негативный контроль** (только для варианта A): временная перестановка `uU`/`uV` в шейдере валит Web-пробу;
   нормативный шейдер восстановлен, проба снова проходит. Оба вывода — в отчёт.

#### Scope
- `example/integration_test/helpers/shader_probe_cases.dart`, `shader_probe_native_test.dart` (вызов общих случаев),
  `shader_probe_web_test.dart`; `tool/ci/web.ps1` (решение 4).
- Вариант B: `lib/src/widgets/yuv_frame_renderer.dart` (выключатель, dartdoc). README — вариант A или B, одна фраза;
  `CHANGELOG.md` — только вариант B («шейдер на Web выключен»).

#### Constraints
- Native, `lib/src/yuv/impl/**`, шейдер (кроме временной правки решения 5) и WASM-сборку не трогать.
- Браузерные прогоны — по `todo.md`, «Окружение → ChromeDriver»; вердикт `flutter drive` — по строке
  `All tests passed`.

#### Definition of Done
- [ ] Общие случаи вынесены; native-проба на Windows проходит без изменения вывода.
- [ ] Web-проба выполнена; вариант A/B/C выбран по признаку, максимумы или ошибка — в отчёте.
- [ ] `tool/ci/web.ps1` проходит целиком: `sources=14; integration cases=63`.
- [ ] Вариант A — негативный контроль решения 5 в отчёте.

#### Validation
Ключи: `example/integration_test/*` → `all`, `tool/ci/web.*` → `web`, `lib/*` → `vm example`. Ветка пула — `all/PAR-WEB`.

- `dart format --line-length 150`; `flutter analyze` в корне и в `example/`.
- `pwsh -File tool/ci/web.ps1`, `pwsh -File tool/ci/windows.ps1`, `pwsh -File tool/ci/vm.ps1`, `pwsh -File tool/ci/example.ps1`.
- Probe `windows`: в составе `tool/ci/windows.ps1`.

#### Executor Report
#### Review
