# SPM 1 — Общий каталог `darwin/` для iOS и macOS
**Status:** BLOCKED · **Tier:** T3 · **Owner:** CLEAN 2 · **Depends On:** CLEAN 2 · **Probe:** none

#### Goal
D-12, шаг 1 из 4 (SPM 1 → SPM 2 → SPM 3, SPM 4). Свести Apple-часть плагина из `ios/` и `macos/` в один
каталог `darwin/` с раскладкой Swift Package Manager (`darwin/yuv_ffi/Sources/yuv_ffi/`), сохранив сборку через
CocoaPods. `Package.swift` здесь не создаётся: без него Flutter собирает плагин через CocoaPods, и текущие
`tool/ci/ios.sh` / `tool/ci/macos.sh` доказывают, что поведение не изменилось.

#### Architect Decision
1. **Native-исходники не переносятся.** `src/` остаётся единственным источником C для CMake (Android, Windows,
   Linux, VM-тесты), ffigen и Apple. Изменений `src/` нет; D-17 не затрагивается.
2. **Переходники — по одному на единицу трансляции.** Для каждой записи `set(SOURCES …)` в `src/CMakeLists.txt`
   создаётся `darwin/yuv_ffi/Sources/yuv_ffi/<basename>.c`, где `<basename>` — имя файла источника, с одной
   директивой `#include "../../../../src/<путь от src/>"` (четыре `..`: `Sources/yuv_ffi` → `Sources` →
   `darwin/yuv_ffi` → `darwin` → корень). Набор единиц трансляции совпадает с CMake, поэтому прежнее правило
   «`yuv_rotate_v1.c` и `yuv_flip_v1.c` — в разных переходниках» отпадает. Basename-ы в списке уникальны.
   Сейчас в списке 16 файлов: `yuv_ffi.c`, `checked_arithmetic.c`, `validated_view.c`, `yuv_validate_v1.c`,
   `yuv_kernel_v1.c`, `yuv_convert_v1.c`, `yuv_black_white_v1.c`, `yuv_grayscale_v1.c`, `yuv_negate_v1.c`,
   `yuv_gaussian_blur_v1.c`, `yuv_mean_blur_v1.c`, `yuv_box_blur_v1.c`, `yuv_crop_v1.c`, `yuv_flip_v1.c`,
   `yuv_rotate_v1.c`, `yuv_chroma_swap_v1.c`.
3. **`sharedDarwinSource: true`** у `ios` и `macos` в `pubspec.yaml` (вместе с `ffiPlugin: true`): один podspec и
   в SPM 2 один `Package.swift` на обе платформы, как в шаблоне Flutter `plugin_darwin_spm`.
4. **Podspec `darwin/yuv_ffi.podspec`** по шаблону `plugin_darwin_spm` Flutter 3.44:
   - метаданные (`name`, `summary`, `description`, `homepage`, `license`, `author`) — из нынешнего
     `ios/yuv_ffi.podspec`; `s.version` — версия из `pubspec.yaml`;
   - `s.source = { :path => '.' }`, `s.source_files = 'yuv_ffi/Sources/yuv_ffi/*.c'` — только переходники;
   - `s.ios.deployment_target = '13.0'`, `s.osx.deployment_target = '10.15'` (минимум самого Flutter 3.44 для
     macOS — 10.15, прежние 10.11 недостижимы);
   - `s.ios.dependency 'Flutter'`, `s.osx.dependency 'FlutterMacOS'`;
   - `s.ios.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }`,
     `s.osx.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }`, `s.swift_version = '5.0'`;
   - комментарий о переходниках переписать под новую раскладку (английский, D-7).
5. **Карта проверок.** `darwin/*` получает ключи `ios macos`; правила `ios/*` и `macos/*` для удалённых каталогов
   плагина убираются, `example/ios/*` и `example/macos/*` остаются.

#### Scope
Worktree `.worktrees/SPM-1`, ветка `task/SPM-1` от `dev`.

- `pubspec.yaml`: `sharedDarwinSource: true` у `ios` и `macos`.
- Создать `darwin/yuv_ffi.podspec` и 16 переходников `darwin/yuv_ffi/Sources/yuv_ffi/*.c` (решения 2 и 4).
  У каждого переходника — короткий английский комментарий: зачем он нужен и что список сверяет
  `test/apple_forwarder_sources_test.dart`.
- `git rm` каталогов плагина `ios/` (`ios/Classes/*`, `ios/yuv_ffi.podspec`) и `macos/` (`macos/Classes/*`,
  `macos/yuv_ffi.podspec`). **`example/ios` и `example/macos` не удалять.**
- `test/apple_forwarder_sources_test.dart`: один каталог `darwin/yuv_ffi/Sources/yuv_ffi`, префикс
  `../../../../src/`; добавить инварианты «каждый переходник содержит ровно один `#include` `.c`» и «имя
  переходника совпадает с basename включаемого источника»; негативные контроли перевести на новый каталог;
  dartdoc обновить под новую раскладку.
- `tool/ci/scope_guard.sh` (`path_keys`): правило `darwin/*` → `ios macos` перед `lib/*`; `macos/*|example/macos/*`
  → `example/macos/*`; `ios/*|example/ios/*` → `example/ios/*`. Та же правка в таблице «Локальные проверки по
  изменённым путям» в `AGENTS.md`.
- `example/ios/Podfile.lock`, `example/macos/Podfile.lock`: закоммитить то, что даст `pod install` на Mac (путь
  `.symlinks/plugins/yuv_ffi/darwin`, новая версия pod).

#### Constraints
- Не трогать `src/`, `lib/`, `example/lib/`, сгенерированные bindings. `Package.swift` не создавать (SPM 2).
- Не менять `tool/ci/ios.sh`, `tool/ci/macos.sh`, `tool/ci/drive.sh` (SPM 3).
- Комментарии, dartdoc, сообщения коммитов — на английском; карточка и отчёт — на русском.
- Зависимость от CLEAN 2: она может поднять версию в `ios|macos/*.podspec`, которые здесь удаляются. Ветку
  создавать от `dev` после слияния CLEAN 2, версию podspec брать из `pubspec.yaml`.

#### Definition of Done
- [ ] Каталогов плагина `ios/` и `macos/` нет; есть `darwin/yuv_ffi.podspec` и 16 переходников, по одному на
      источник из `set(SOURCES …)`.
- [ ] `pubspec.yaml` объявляет `sharedDarwinSource: true` для `ios` и `macos`; версия podspec = версия pubspec.
- [ ] `test/apple_forwarder_sources_test.dart` проверяет новый каталог, включая два новых инварианта и негативные
      контроли, и проходит.
- [ ] `tool/ci/scope_guard.sh` и таблица в `AGENTS.md` знают `darwin/*`.
- [ ] `tool/ci/macos.sh` и `tool/ci/ios.sh` проходят на Mac (сборка через CocoaPods из `darwin/`).
- [ ] В репозитории нет ссылок на `ios/Classes` и `macos/Classes` вне `tasks/`.

#### Validation
`pubspec.yaml` и `tool/ci/scope_guard.sh` дают ключ `all` (`AGENTS.md`, таблица путей).

- Windows, из корня worktree: `flutter test test/apple_forwarder_sources_test.dart`; `pwsh -File tool/ci/smoke.ps1`,
  `vm.ps1`, `windows.ps1`, `example.ps1`, `android.ps1`; `web.ps1` — если major-версии Chrome и ChromeDriver
  совпадают (`todo.md`, «Окружение → ChromeDriver»), иначе записать, почему не запущен.
- `bash -n tool/ci/scope_guard.sh`.
- Mac (`todo.md`, «Окружение → Mac»): дерево — tar через ssh в `~/claude-work/yuv_ffi-SPM-1`, каждая команда с
  преамбулой `mac-env.sh`; `bash tool/ci/macos.sh`, `bash tool/ci/ios.sh`. Если `flutter build macos --release`
  виснет в `gen_snapshot` (известная проблема этого Mac через ssh), записать это и прогнать
  `flutter build macos --debug` и `bash tool/ci/drive.sh integration_test/native_app_runtime_smoke_test.dart macos`.
- В выводе `pod install` (iOS и macOS) — `yuv_ffi` из `.symlinks/plugins/yuv_ffi/darwin`.
- `dart pub publish --dry-run`: в списке файлов есть `darwin/yuv_ffi.podspec` и `darwin/yuv_ffi/Sources/yuv_ffi/*.c`,
  нет `ios/Classes`, `macos/Classes`, `.worktrees/`.
- `git grep -n -e "ios/Classes" -e "macos/Classes" -- . ":!tasks"` — пусто.
- В Executor Report — команды и хвосты вывода (строки `PASS …`, `All tests passed`, итог `flutter test`).

#### Executor Report
WIP, остановлено по приказу Engineer; статус карточки не менялся. Сделано (коммиты all/STAGE3-SPM-wip):
- darwin/yuv_ffi.podspec, 16 переходников darwin/yuv_ffi/Sources/yuv_ffi/*.c, sharedDarwinSource в pubspec.yaml, git rm ios/ и macos/ (плагин), scope_guard.sh и таблица AGENTS.md (darwin/* -> ios macos), test/apple_forwarder_sources_test.dart (новые инварианты и негативные контроли), Podfile.lock example/ios и example/macos.
- Проверено: flutter test test/apple_forwarder_sources_test.dart -> All tests passed (8); bash -n tool/ci/scope_guard.sh ok; git grep ios/Classes|macos/Classes вне tasks -> пусто; dart pub publish --dry-run: darwin/yuv_ffi.podspec и darwin/yuv_ffi/Sources/yuv_ffi/*.c есть, ios/Classes и macos/Classes нет.
- Windows (RUNNER_TEMP в отдельный каталог, иначе общий кэш cmake от другого worktree ломает vm.ps1): smoke.ps1 0; vm.ps1 573/573; windows.ps1 PASS smoke+probe_native; android.ps1 PASS на emulator-5554; example.ps1 (FLUTTER_VERSION=3.44.9) ok; web.ps1 из PowerShell tool: Web CI passed (Chrome 154 = ChromeDriver 154; из Git Bash pwsh падал на `git` not recognized из-за PATH после emsdk).
- Mac (CocoaPods из darwin/): bash tool/ci/macos.sh EXIT 0 (flutter build macos --release 39 s, без зависания gen_snapshot; PASS native_app_runtime_smoke и probe_native); bash tool/ci/ios.sh EXIT 0 (iOS 18.6, PASS smoke и probe_native). pod install: yuv_ffi из .symlinks/plugins/yuv_ffi/darwin.
- Заметка: на Mac git archive даёт CRLF в .sh, нужно sed 's/$//' после распаковки.
Не завершено: формальная сверка отчёта/DoD Reviewer-ом; других хвостов нет.
#### Review
Вердикт: ACCEPTED. Reviewed head: 1a38dd0 (пул STAGE3-SPM целиком, diff `dev...HEAD`).
- DoD сверен с диффом и отчётами Executor: переходники/podspec/Package.swift/заголовок соответствуют решениям карточек; отчёты содержат команды и результаты, согласованы с закоммиченными скриптами (определение режима по Podfile.lock, CocoaPods-проход в копии с pod install заранее, выбор iOS 18.x, git status в macos.sh).
- Windows (Reviewer, из корня worktree): `pwsh -File tool/ci/example.ps1` -> exit 0 (pub get, analyze, build web); `flutter test test/apple_forwarder_sources_test.dart` -> All tests passed (8); `bash -n` scope_guard/ios/macos -> ok; `smoke.ps1` -> exit 0; `vm.ps1` -> 573/573; `dart pub publish --dry-run` -> 0 warnings, darwin/yuv_ffi.podspec, darwin/yuv_ffi/Package.swift, Sources/*.c есть, ios/Classes и macos/Classes и .worktrees/ нет; `git grep ios/Classes|macos/Classes` вне tasks -> пусто.
- Mac не перезапускался: свидетельства конкретны и непротиворечивы. windows/android/web.ps1 не запускались: после зелёных прогонов Executor изменились только example/pubspec.yaml (ключ flutter.config, покрыт example.ps1), example/ios, example/macos, tool/ci/ios.sh|macos.sh и документация.
- Blocking: нет. Advisory: нет.
