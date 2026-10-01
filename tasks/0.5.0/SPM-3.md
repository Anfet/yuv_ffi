# SPM 3 — CI: проверка SPM и CocoaPods в `ios.sh` и `macos.sh`
**Status:** BLOCKED · **Tier:** T2 · **Owner:** SPM 2 · **Depends On:** SPM 2 · **Probe:** none

#### Goal
D-12, шаг 3 из 4. После SPM 2 example собирает плагин через SPM, и путь CocoaPods в CI больше не проверяется.
Вернуть его отдельным коротким проходом, проверять в скриптах, каким путём плагин реально собран, и выбирать
iOS-симулятор детерминированно: ML Kit в example не поддерживает arm64 на iOS 26+ Simulator, а на iOS 18.6
работает.

#### Architect Decision
1. **Основной проход — SPM** (как настроил SPM 2) и сохраняет нынешний набор: сборка, runtime smoke, все
   `*_native_test.dart`. После сборки скрипт проверяет режим: `yuv_ffi` отсутствует в
   `example/<платформа>/Podfile.lock`. Иначе — выход с ненулевым кодом и сообщением, что плагин собран не через SPM.
2. **CocoaPods-проход — короткий:** сборка и только `integration_test/native_app_runtime_smoke_test.dart`.
   - Выполняется в копии во временном каталоге (`mktemp -d` под `${RUNNER_TEMP:-${TMPDIR:-/tmp}}`), удаляемом
     через `trap`. Копируется `example/` без `build/`, `.dart_tool/`, `Pods/`, `ephemeral/`.
   - В pubspec копии путь к `yuv_ffi` — абсолютный путь к корню репозитория, `enable-swift-package-manager: false`.
   - После сборки — проверка режима: `yuv_ffi` есть в `Podfile.lock` копии.
   - `flutter drive` запускается через копию `tool/ci/drive.sh`, положенную в `<tmp>/tool/ci/drive.sh` рядом с
     `<tmp>/example`: скрипт сам находит `example` относительно себя, поэтому контракт успеха (exit 0 и
     `All tests passed`) остаётся тем же без правки `drive.sh`.
3. **Симулятор iOS:** выбирать доступный iPhone с runtime iOS 18.x
   (`xcrun simctl list devices available -j`, ключ runtime `com.apple.CoreSimulator.SimRuntime.iOS-18-*`). Если его
   нет — выход с сообщением о причине: ML Kit без arm64-среза для iOS 26+ Simulator.
4. Скрипты не изменяют отслеживаемые файлы: после прогона `git status --porcelain` пуст (не считая уже
   игнорируемых артефактов сборки).

#### Scope
Worktree `.worktrees/SPM-3`, ветка `task/SPM-3` от `dev` после слияния SPM 2 (скрипты проверяются локально на
Mac, ветка `ci/**` не нужна).

- `tool/ci/ios.sh`: решения 1–3.
- `tool/ci/macos.sh`: решения 1, 2 и 4. Основная сборка `flutter build macos --release` остаётся;
  CocoaPods-проход собирает debug.

#### Constraints
- Не менять `tool/ci/drive.sh`, `tool/ci/_common.ps1`, workflow-файлы, `example/` и код пакета.
- Стиль скриптов — как в нынешних `ios.sh`/`macos.sh` (`set -euo pipefail`, `run_quiet` в `macos.sh`); комментарии
  на английском и только там, где причина неочевидна (почему копия, почему iOS 18).
- Время CocoaPods-прохода держать минимальным: никаких `*_native_test.dart` в нём.

#### Definition of Done
- [ ] Оба скрипта проходят на Mac целиком: SPM-проход и CocoaPods-проход, обе проверки режима зелёные.
- [ ] Негативный контроль: при `enable-swift-package-manager: false` в example (временная правка в копии дерева)
      проверка SPM-режима падает с понятным сообщением.
- [ ] iOS-симулятор выбирается по runtime iOS 18.x; сообщение при его отсутствии проверено (например, подменой
      фильтра на несуществующий runtime в копии скрипта).
- [ ] После прогонов `git status --porcelain` пуст.

#### Validation
Ключи: `tool/ci/ios.*` → `ios`, `tool/ci/macos.*` → `macos`; проверки на Windows не нужны.

- Mac (`todo.md`, «Окружение → Mac», tar через ssh в `~/claude-work/yuv_ffi-SPM-3`, преамбула `mac-env.sh`):
  `bash tool/ci/ios.sh`, `bash tool/ci/macos.sh`, затем `git status --porcelain` (дерево на Mac распаковать с
  `.git` или сверить список файлов до/после — способ записать). Если release-сборка macOS виснет в
  `gen_snapshot` (известная проблема ssh-сессии), записать это и подтвердить остальную часть скрипта, временно
  подставив debug в копии скрипта; release проверит CI пачки.
- Негативные контроли из DoD — с выводом в Executor Report.
- `bash -n tool/ci/ios.sh tool/ci/macos.sh`.

#### Executor Report
Выполнено напрямую на Mac в репозитории `/Users/oleg/projects/yuv_ffi` (каталог называется `yuv_ffi`). Коммиты: 6cfb275 (скрипты), 1458e09 (pod install в iOS-копии).
- `tool/ci/ios.sh`: выбор симулятора по runtime `SimRuntime.iOS-18-*` (jq, самый новый iOS 18.x, iPhone); сообщение при отсутствии; после SPM-сборки проверка «yuv_ffi нет в example/ios/Podfile.lock»; CocoaPods-проход в копии (`mktemp`, trap, rsync без build/.dart_tool/Pods/ephemeral, абсолютный путь к yuv_ffi, `enable-swift-package-manager: false`, копия drive.sh в `<tmp>/tool/ci`), проверка «yuv_ffi есть в Podfile.lock копии», drive только `native_app_runtime_smoke_test`.
- `tool/ci/macos.sh`: то же для macOS (основная сборка `--release`, CocoaPods-проход `--debug`), в конце проверка `git status --porcelain` пуст.
- Находка: первый `flutter build ios --simulator` в копии без `Pods/` падал: `Error (Xcode): Linker command failed` / `ld: framework 'Pods_Runner' not found` (второй запуск в той же копии проходит). Исправление: в копии перед сборкой `(cd ios && pod install)`; проверено — сборка проходит с первого раза.
- Результаты: `bash tool/ci/macos.sh` EXIT 0: `ok flutter build macos --release (39 s)`, `PASS native_app_runtime_smoke_test on macos`, `PASS probe_native_test on macos`, `ok flutter build macos --debug (27 s)`, `PASS native_app_runtime_smoke_test on macos` (CocoaPods); повторный прогон EXIT 0, `git status --porcelain` пуст. `bash tool/ci/ios.sh` EXIT 0 (симулятор iPhone 16 Pro, iOS 18.6): `PASS native_app_runtime_smoke_test`, `PASS probe_native_test`, `✓ Built build/ios/iphonesimulator/Runner.app`, `PASS native_app_runtime_smoke_test` (CocoaPods); `git status --porcelain` после прогона пуст.
- Негативные контроли (копия дерева вне репозитория `$TMPDIR/neg/yuv_ffi`): `enable-swift-package-manager: false` в example → `macos.sh` EXIT 1: `yuv_ffi is listed in example/macos/Podfile.lock: the plugin was not built through Swift Package Manager.`; подмена фильтра на `iOS-99-` → `ios.sh` EXIT 1: `No available iPhone simulator with an iOS 18.x runtime was found (ML Kit has no arm64 slice for the iOS 26+ Simulator).`
- `bash -n tool/ci/ios.sh tool/ci/macos.sh` — ок.
- Не запускалось: нет Windows и отдельных запусков по CI на `ci/**` не было.
#### Review
Вердикт: ACCEPTED. Reviewed head: 1a38dd0 (пул STAGE3-SPM целиком, diff `dev...HEAD`).
- DoD сверен с диффом и отчётами Executor: переходники/podspec/Package.swift/заголовок соответствуют решениям карточек; отчёты содержат команды и результаты, согласованы с закоммиченными скриптами (определение режима по Podfile.lock, CocoaPods-проход в копии с pod install заранее, выбор iOS 18.x, git status в macos.sh).
- Windows (Reviewer, из корня worktree): `pwsh -File tool/ci/example.ps1` -> exit 0 (pub get, analyze, build web); `flutter test test/apple_forwarder_sources_test.dart` -> All tests passed (8); `bash -n` scope_guard/ios/macos -> ok; `smoke.ps1` -> exit 0; `vm.ps1` -> 573/573; `dart pub publish --dry-run` -> 0 warnings, darwin/yuv_ffi.podspec, darwin/yuv_ffi/Package.swift, Sources/*.c есть, ios/Classes и macos/Classes и .worktrees/ нет; `git grep ios/Classes|macos/Classes` вне tasks -> пусто.
- Mac не перезапускался: свидетельства конкретны и непротиворечивы. windows/android/web.ps1 не запускались: после зелёных прогонов Executor изменились только example/pubspec.yaml (ключ flutter.config, покрыт example.ps1), example/ios, example/macos, tool/ci/ios.sh|macos.sh и документация.
- Blocking: нет. Advisory: нет.
