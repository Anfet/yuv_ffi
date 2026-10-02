# CI 3 — VM-CI: пакет не собирается на минимальном Flutter 3.38
**Status:** ENGINEER_REQUIRED · **Tier:** — · **Owner:** Engineer · **Depends On:** — · **Probe:** —

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

Расследование и исправление — только по команде Engineer (правило 4).

#### Architect Decision
#### Scope
#### Constraints
#### Definition of Done
#### Validation
#### Executor Report
#### Review
