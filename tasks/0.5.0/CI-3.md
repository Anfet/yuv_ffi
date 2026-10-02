# CI 3 — VM-CI: пакет не собирается на минимальном Flutter 3.38
**Status:** BLOCKED · **Tier:** T2 · **Owner:** CI 2 · **Depends On:** CI 2 (тот же пул) · **Probe:** windows

#### Goal
Фактическая карточка отказа post-merge CI (правило 4 `todo.md`). Отложенный CI этапов 4–5 прогнан тегом
`ci/all/CI-1` на SHA `af895ae`. Workflow `CI VM` упал на матрице минимальной версии.

- Workflow / run / job: `CI VM` ([run 37058238047](https://github.com/Anfet/yuv_ffi/actions/runs/37058238047)),
  джоба `vm (3.38.10)` ([job 111008126925](https://github.com/Anfet/yuv_ffi/actions/runs/37058238047/job/111008126925)).
  Джоба `vm (3.44.9)` того же run — зелёная.
- Упавший шаг: `Analyze and test VM`, `flutter analyze --no-fatal-infos lib test`.
- Фрагмент ошибки:
  ```text
  error - The named parameter 'filterQuality' isn't defined - lib\src\widgets\yuv_frame_renderer.dart:92:50 - undefined_named_parameter
  ```
- Известное:
  - строка `_shader.setImageSampler(0, texture._image, filterQuality: FilterQuality.none);` пришла в SHADER 2
    (`7f4425c`, этап 4);
  - `pubspec.yaml` обещает `flutter: '>=3.38.0'` (README: «Flutter 3.38 or later»), но параметра `filterQuality` у
    `FragmentShader.setImageSampler` в 3.38 нет: в `sky_engine` 3.38.7 — `setImageSampler(int index, Image image)`;
    в 3.41.9 и 3.44 — `{FilterQuality filterQuality = FilterQuality.none}`. То есть для пользователей Flutter
    3.38–3.40 опубликованный пакет **не компилируется**;
  - значение по умолчанию в 3.41+ — то же, что передаётся явно (`FilterQuality.none`).
- Варианты:
  1. **Убрать аргумент** — `setImageSampler(0, texture._image)`. На 3.41+ поведение не меняется (то же значение по
     умолчанию). На 3.38–3.40 фильтрация сэмплера — та, что была у движка до появления параметра; её нужно
     подтвердить шейдерной пробой на 3.38 (`shader_probe_native_test.dart`, на Mac есть Flutter 3.38.7).
  2. **Поднять минимум до Flutter 3.41** (`pubspec.yaml`, README, CHANGELOG, матрица `ci-vm.yml`). Проще, но
     отсекает пользователей 3.38–3.40.
  Рекомендация — вариант 1 с пробой на 3.38; если проба на 3.38 расходится с CPU, — вариант 2.
- Критерий исправления: `vm (3.38.10)` и `vm (3.44.9)` зелёные (`ci/vm/<метка>`), шейдерная проба проходит на
  минимальной поддерживаемой версии.

Engineer дал команду чинить (03.10.2026).

#### Architect Decision
1. **Убрать аргумент** (вариант 1 Goal): в `lib/src/widgets/yuv_frame_renderer.dart` —
   `_shader.setImageSampler(0, texture._image);`. На Flutter 3.41+ поведение то же: значение по умолчанию —
   `FilterQuality.none`.
2. **Проверка на минимальной версии.** На Linux VM поставить Flutter 3.38.10 рядом с 3.44.9
   (`~/storage/flutter_3.38/flutter`, `git clone --depth 1 -b 3.38.10`), и на нём:
   - `flutter analyze` и `flutter test` в корне пакета;
   - шейдерная проба: в `example/` `flutter create --platforms=linux .`, затем
     `xvfb-run -a bash tool/ci/drive.sh integration_test/shader_probe_native_test.dart linux` — строки `SHADER PROBE`
     в отчёт.
   Та же проба на 3.44.9 — для сравнения.
3. **Варианты по результату** (по порядку):
   - проба на 3.38.10 проходит (`max_diff <= 1`) → готово;
   - на 3.38.10 шейдер не грузится на Linux под xvfb (`hasShader == false`, проба падает на `expect(hasShader)`) →
     повторить пробу на Mac с Flutter 3.38.7 (`~/storage/flutter_3.38.7`, macOS desktop, debug — release на Mac
     виснет); прошла → готово;
   - проба расходится с CPU на 3.38 → вариант 2 Goal: вернуть аргумент и поднять минимум до Flutter 3.41
     (`pubspec.yaml` `flutter: '>=3.41.0'`, README «Flutter 3.41 or later», CHANGELOG, матрица `ci-vm.yml`
     `'3.41.x'` — последний патч 3.41), расхождение — таблицей в отчёт.

#### Scope
- `lib/src/widgets/yuv_frame_renderer.dart` (одна строка).
- Только при варианте 2: `pubspec.yaml`, `README.md`, `CHANGELOG.md`, `.github/workflows/ci-vm.yml`.

#### Constraints
- Шейдер и native не трогать.

#### Definition of Done
- [ ] `flutter analyze` и `flutter test` проходят на 3.38.10 и 3.44.9 (VM).
- [ ] Шейдерная проба — на минимальной поддерживаемой версии и на 3.44.9, строки `SHADER PROBE` в отчёте.
- [ ] Выбранный вариант и причина — в отчёте.

#### Validation
Ключи: `lib/*` → `vm example`; при варианте 2 — `all`.

- `pwsh -File tool/ci/vm.ps1`, `pwsh -File tool/ci/example.ps1`; Probe `windows` — `pwsh -File tool/ci/windows.ps1`.
- `dart format --line-length 150`.

#### Executor Report
#### Review
