# CI 3 — VM-CI: пакет не собирается на Flutter 3.38; минимум — 3.41
**Status:** TODO · **Tier:** T2 · **Owner:** STAGE6 · **Depends On:** — · **Probe:** windows

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
**Engineer (03.10.2026): минимум пакета поднимается до Flutter 3.41 (D-24).** Причина: example требует Dart 3.11
(`camera_desktop` 2.0.0, `sdk: ^3.11.0`, коммит `af5ea6d`), поэтому на 3.38–3.40 шейдерную пробу не запустить, а
поддержку этих версий без пробы не обещаем. Пакет и example получают один минимум. Прежнее решение (убрать аргумент,
проба на 3.38) отменено.

1. **Сэмплер.** Вернуть явный аргумент: `_shader.setImageSampler(0, texture._image, filterQuality: FilterQuality.none);`
   — на 3.41+ он есть, а явное значение не зависит от умолчания движка.
2. **Минимум.**
   - `pubspec.yaml`: `sdk: ^3.11.0`, `flutter: '>=3.41.0'`;
   - `README.md`, «Requirements»: Dart 3.11 or later, Flutter 3.41 or later;
   - `CHANGELOG.md`, `0.5.0-dev.1` → «Breaking changes»: «Raised the minimum supported SDK to Dart `^3.11.0` /
     Flutter `>=3.41.0`.» (строка 0.4.0 про 3.38 — история, не трогать);
   - `.github/workflows/ci-vm.yml`: в матрице `'3.38.10'` → последний патч 3.41
     (`git ls-remote --tags https://github.com/flutter/flutter 'refs/tags/3.41.*'`; на Mac есть 3.41.9).
   `example/pubspec.yaml` уже требует `>=3.11.0` — не менять.
3. **Проверка на минимуме — Linux VM.** Поставить выбранный патч 3.41 рядом с 3.44.9
   (`~/storage/flutter_3.41/flutter`, `git clone --depth 1 -b <патч>`); 3.38.10 с VM можно удалить. На 3.41:
   - в корне — как `tool/ci/vm.ps1`: `flutter pub get --no-example`, `flutter analyze --no-fatal-infos lib test`,
     `flutter test`;
   - шейдерная проба: в `example/` `flutter create --platforms=linux .`, затем
     `xvfb-run -a bash tool/ci/drive.sh integration_test/shader_probe_native_test.dart linux` — строки `SHADER PROBE`
     в отчёт. Проба на 3.44.9 уже прошла (Executor Report) — повторить после решения 1, она дешёвая.
   Если на 3.41 под xvfb шейдер не грузится (`hasShader == false`) — проба на Mac с 3.41.9 (`~/storage/flutter_3.41.9`
   или где лежит, macOS desktop, debug).

#### Scope
- `lib/src/widgets/yuv_frame_renderer.dart` (одна строка), `pubspec.yaml`, `README.md`, `CHANGELOG.md`,
  `.github/workflows/ci-vm.yml`.

#### Constraints
- Шейдер и native не трогать; зависимости пакета и example не менять.
- CI-тег на ветке не нужен: `ci-vm.yml` меняет только версию в матрице; `ci/vm` — после слияния, на выходе из этапа.

#### Definition of Done
- [ ] На Linux VM на 3.41.x и 3.44.9: `pub get --no-example`, `analyze`, `flutter test` в корне — PASS.
- [ ] Шейдерная проба на 3.41.x и 3.44.9 — PASS, строки `SHADER PROBE` в отчёте.
- [ ] `pubspec.yaml`, README, CHANGELOG, матрица `ci-vm.yml` — по решению 2.

#### Validation
Ключи: `pubspec.yaml` → `all`; ветка `all/CLEAN-3` покрывает.

- `dart format --line-length 150` для изменённого Dart-файла.
- `pwsh -File tool/ci/vm.ps1`, `pwsh -File tool/ci/example.ps1`; Probe `windows` — `pwsh -File tool/ci/windows.ps1`.

#### Executor Report
03.10.2026:

- `_shader.setImageSampler(0, texture._image);` собран без `filterQuality`.
- На Linux VM установлен Flutter 3.38.10 (Dart 3.10.9). `flutter pub get` останавливается до analyze/test/probe:
  `yuv_ffi_example requires SDK version >=3.11.0`.
- Причина порога — намеренная: commit `af5ea6d` поднял `example/pubspec.yaml` с Dart 3.10 до 3.11 для
  `camera_desktop`. Flutter 3.38.10 предоставить Dart 3.11 не может.
- На Flutter 3.44.9 Linux shader probe прошла:
  `PASS integration_test/shader_probe_native_test.dart on linux`, `CI3_SHADER_344_EXIT=0`.
- Требуется решение Engineer по публичному минимуму. Вариант 2 Architect Decision поднимает его до Flutter 3.41;
  вариант 1 требует отдельного контракта/версии зависимостей example и не входит в текущий Scope.

#### Review
