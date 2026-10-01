# SPM 2 — `Package.swift` и сборка example через SPM
**Status:** BLOCKED · **Tier:** T2 · **Owner:** SPM 1 · **Depends On:** SPM 1 · **Probe:** none

#### Goal
D-12, шаг 2 из 4. Добавить `darwin/yuv_ffi/Package.swift`, чтобы Flutter 3.44 (SPM включён по умолчанию) собирал
плагин через Swift Package Manager, а CocoaPods оставался рабочим запасным путём. Example переводится на SPM явно,
так что `tool/ci/ios.sh` и `tool/ci/macos.sh` без правок начинают проверять SPM-путь.

#### Architect Decision
1. **Манифест** `darwin/yuv_ffi/Package.swift`:

   ```swift
   // swift-tools-version: 5.9
   import PackageDescription

   let package = Package(
       name: "yuv_ffi",
       platforms: [
           .iOS("13.0"),
           .macOS("10.15"),
       ],
       products: [
           .library(name: "yuv-ffi", type: .dynamic, targets: ["yuv_ffi"]),
       ],
       targets: [
           .target(name: "yuv_ffi"),
       ]
   )
   ```

   - Имя продукта `yuv-ffi`: Flutter подключает продукт плагина по имени пакета с дефисами вместо `_`
     (`swift_package_manager.dart`, `SwiftPackageTargetDependency.product`).
   - `type: .dynamic` обязателен, с английским комментарием над продуктом. Dart находит символы через
     `DynamicLibrary.process()` (`lib/src/loader/impl/loader_io.dart`). Из статической библиотеки линковщик
     берёт только объектные файлы, на которые есть ссылки, а на C-функции из Swift/ObjC никто не ссылается, и
     все 11 символов `yuv_*_v1` пропали бы. Динамический продукт встраивается в приложение как framework, и его
     экспорт остаётся виден процессу; `FlutterGeneratedPluginSwiftPackage` статический и именно для этого
     пробрасывает динамические зависимости в Runner.
   - Зависимости от `FlutterFramework` нет: плагин не использует API Flutter. Если `flutter build` её требует,
     добавить ровно как в шаблоне `plugin_darwin_spm` и записать в отчёт; это не повод останавливаться.
   - Флаги оптимизации не задаются: SPM-сборка совпадает с CocoaPods по флагам Release; заявлений о скорости нет.
2. **Публичный заголовок** `darwin/yuv_ffi/Sources/yuv_ffi/include/yuv_ffi/yuv_ffi.h` — переходник на
   `src/yuv_ffi.h`: `#include "../../../../../../src/yuv_ffi.h"` (шесть `..`). SPM строит из `include/` модуль
   C-цели. В CocoaPods заголовок не попадает: `s.source_files` — только `*.c` (SPM 1).
3. **Example на SPM явно:** в `example/pubspec.yaml`, в секцию `flutter:`, добавить
   `config: { enable-swift-package-manager: true }` (блочным YAML). Настройка в pubspec приоритетнее глобальной
   `flutter config` Mac-раннера, поэтому режим не зависит от машины. Изменения, которые Flutter внесёт в
   `example/ios` и `example/macos` при миграции (`project.pbxproj`, `Podfile.lock`, `Package.resolved`, если
   появится), коммитятся. Плагины без SPM (ML Kit и др.) остаются на CocoaPods — смешанный режим штатный.
4. **Запасной путь — CocoaPods.** Приложение с `enable-swift-package-manager: false` собирает плагин из
   `darwin/yuv_ffi.podspec`; SPM 2 проверяет это вручную, SPM 3 — в CI-скриптах.
5. **Варианты при сбое.** Ниже два места, где возможен сбой, и варианты исправления. Проверять по порядку.
   Принимается первый вариант, который проходит всю Validation. В Executor Report записать: какой вариант
   выбран, почему не прошли предыдущие (команда и хвост лога), ссылку на документацию, подтверждающую
   поведение. Если не прошёл ни один — `ARCHITECT_REQUIRED` с результатами каждого варианта.

   **A. Под SPM не находится `#include "../../../../src/…"`.** Flutter подключает пакет через симлинк
   `…/Packages/.packages/<plugin>` → `darwin/yuv_ffi` (`swift_package_manager.dart`, `_createPluginSymlink`),
   и путь с `..` может разрешиться относительно симлинка, а не реального каталога.
   - A1 — базовый: относительные переходники из SPM 1, без изменений.
   - A2 — путь поиска от реального корня плагина. В `Package.swift` вычислить корень через
     `URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()` и три `deletingLastPathComponent()`, затем
     `cSettings: [.unsafeFlags(["-I", <корень>])]`. Переходники переписать на `#include "src/<путь от src/>"`.
     В podspec добавить `'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/.."'` в `pod_target_xcconfig` обеих
     платформ. Префикс в `test/apple_forwarder_sources_test.dart` заменить на `src/`. Отдельно проверить, что
     SPM принимает `unsafeFlags` у пакета-зависимости, подключённого по пути: ограничение относится к
     удалённым зависимостям
     (https://developer.apple.com/documentation/packagedescription/csetting/unsafeflags(_:_:)).
   - Не пробовать `.headerSearchPath("../../../../src")`: путь должен лежать внутри пакета
     (https://developer.apple.com/documentation/packagedescription/csetting/headersearchpath(_:_:)).
   - Вне полномочий исполнителя (это `ENGINEER_REQUIRED`, D-12, D-17): перенос или копирование `src/`,
     симлинки в git.

   **B. Публичный заголовок ломает сборку модуля** (`include of non-modular header inside framework module` и
   подобные).
   - B1 — базовый: переходник `include/yuv_ffi/yuv_ffi.h` → `src/yuv_ffi.h`.
   - B2 — самодостаточный `include/yuv_ffi/yuv_ffi.h` без `#include`, только с английским комментарием:
     ABI потребляется из Dart через FFI, объявления — в `src/yuv_ffi.h`. Объявления не копировать, иначе
     появится вторая копия ABI.
   - B3 — без каталога `include/`, если SPM собирает цель без ошибок и без предупреждения об отсутствии
     публичных заголовков.

#### Scope
Worktree `.worktrees/SPM-2`, ветка `task/SPM-2` от `dev` после слияния SPM 1.

- Создать `darwin/yuv_ffi/Package.swift` и `darwin/yuv_ffi/Sources/yuv_ffi/include/yuv_ffi/yuv_ffi.h`.
- `example/pubspec.yaml`: включить SPM (решение 3); закоммитить порождённые изменения `example/ios/**`,
  `example/macos/**`.

#### Constraints
- Не трогать `src/`, `lib/`, `tool/ci/*`. Переходники `*.c`, podspec и `test/apple_forwarder_sources_test.dart`
  менять только по варианту A2 (решение 5). Тогда добавляется ключ `vm`: запустить `pwsh -File tool/ci/vm.ps1`;
  CocoaPods-проверка из пункта 5 Validation при этом обязательна для iOS и macOS.
- Временные правки для негативного контроля — только в копии вне репозитория или откатываются до коммита.
- Сбои сборки под SPM разбирать по решению 5. Обходы вне полномочий исполнителя не применять.

#### Definition of Done
- [ ] `darwin/yuv_ffi/Package.swift` и публичный заголовок соответствуют решениям 1–2.
- [ ] Example собирается на iOS Simulator и macOS с плагином через SPM: `yuv_ffi` нет в `Podfile.lock`, есть в
      сгенерированном `FlutterGeneratedPluginSwiftPackage`.
- [ ] `native_app_runtime_smoke_test` и `*_native_test.dart` проходят в SPM-режиме на iOS Simulator и macOS
      (`tool/ci/ios.sh`, `tool/ci/macos.sh` без правок).
- [ ] В собранном framework экспортированы все 11 символов `yuv_*_v1` (список —
      `lib/src/yuv/shared/yuv_abi_v1_symbols.dart`).
- [ ] CocoaPods-режим (копия example с `enable-swift-package-manager: false`) собирается, и runtime smoke на
      macOS проходит; `yuv_ffi` в его `Podfile.lock` — из `…/darwin`.
- [ ] Негативный контроль по `type: .dynamic` выполнен и записан.

#### Validation
Ключи: `darwin/*` → `ios macos`, `example/pubspec.yaml` → `example`, `example/ios/*` → `ios`,
`example/macos/*` → `macos`.

- Windows: `pwsh -File tool/ci/example.ps1`.
- Mac (`todo.md`, «Окружение → Mac»: tar через ssh в `~/claude-work/yuv_ffi-SPM-2`, преамбула `mac-env.sh`):
  1. `flutter --version`, `flutter config --list` — в отчёт.
  2. `bash tool/ci/macos.sh`, `bash tool/ci/ios.sh`. Если release-сборка macOS виснет в `gen_snapshot`, записать
     и заменить её на `flutter build macos --debug` плюс тот же `drive.sh` для macOS.
  3. Доказательство SPM-режима: `grep -c yuv_ffi example/ios/Podfile.lock example/macos/Podfile.lock` → 0;
     `yuv_ffi` в `example/{ios,macos}/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift`
     (если путь другой — найти и записать фактический).
  4. `nm -gU` по бинарнику framework плагина в собранном `.app` (`Contents/Frameworks/` для macOS,
     `Frameworks/` для iOS) — 11 строк `_yuv_*_v1`.
  5. CocoaPods-режим: копия `example/` во временный каталог вне репозитория, в её pubspec путь к `yuv_ffi` —
     абсолютный путь к дереву, `enable-swift-package-manager: false`; `flutter build ios --simulator --debug`,
     `flutter build macos --debug`, runtime smoke на macOS через `flutter drive` из копии (успех — строка
     `All tests passed`, exit code `flutter drive` не доказательство); `Podfile.lock` копии содержит `yuv_ffi`.
  6. Негативный контроль: убрать `type: .dynamic` во временной копии, пересобрать macOS, прогнать runtime smoke —
     ожидается провал из-за отсутствующих символов; записать строку ошибки. Если smoke всё же проходит —
     записать это и `nm -gU` бинарника Runner, решение `.dynamic` не менять.
- В Executor Report — команды, хвосты вывода, путь к `.app`, вывод `nm`.

#### Executor Report
WIP, остановлено по приказу Engineer; статус карточки не менялся. Сделано (коммиты all/STAGE3-SPM-wip):
- darwin/yuv_ffi/Package.swift (решение 1, без зависимости FlutterFramework: сборка проходит), include/yuv_ffi/yuv_ffi.h (вариант B1), example/pubspec.yaml: config enable-swift-package-manager: true; изменения Flutter при миграции example/ios и example/macos (project.pbxproj, схемы, Podfile.lock, а также UIScene-миграция AppDelegate.swift/Info.plist и AppFrameworkInfo.plist) закоммичены.
- Вариант A1 (относительные переходники) работает, A2 не потребовался.
- ВАЖНО: Mac-дерево должно лежать в каталоге с именем ровно `yuv_ffi` (например ~/claude-work/SPM-2/yuv_ffi). В каталоге `yuv_ffi-SPM-2` или `yuv_ffi-0.5.0` flutter build падает: "unable to override package 'yuv_ffi' because its identity 'yuv_ffi-spm-2' doesn't match override's identity (directory name) 'yuv_ffi'" (Flutter добавляет ../../../darwin/yuv_ffi в группу pbxproj, SwiftPM сверяет имя каталога корня). Пример вне репозитория с абсолютным путём к yuv_ffi-SPM-2 собирается. Карточка SPM 3 (`~/claude-work/yuv_ffi-SPM-3`) этим затронута.
- Mac: bash tool/ci/macos.sh EXIT 0 (release, PASS smoke и probe_native); bash tool/ci/ios.sh EXIT 0 (iOS 18.6 sim, PASS smoke и probe_native). Режим SPM: grep -c yuv_ffi example/{ios,macos}/Podfile.lock -> 0 и 0; в ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift есть .package(name: "yuv_ffi", path: "../.packages/yuv_ffi") и product yuv-ffi.
- nm -gU: macOS example/build/macos/Build/Products/Release/yuv_ffi_example.app/Contents/Frameworks/yuv-ffi.framework/Versions/A/yuv-ffi -> 11 символов _yuv_*_v1; iOS simulator Runner.app/Frameworks/yuv-ffi.framework/yuv-ffi (только slice x86_64 из-за ML Kit) -> те же 11.
- CocoaPods-режим (копия example вне репозитория, абсолютный путь, SPM=false): flutter build macos --debug ok, flutter build ios --simulator --debug ok (первый запуск дал "Linker command failed" при откате с SPM, повтор прошёл), drive native_app_runtime_smoke на macOS: PASS; Podfile.lock копии содержит yuv_ffi из .symlinks/plugins/yuv_ffi/darwin, Frameworks содержит yuv_ffi.framework.
- Негативный контроль .dynamic (копия без `type: .dynamic`): debug-сборка macOS и drive smoke всё же PASS (debug.dylib содержит 11 символов, nm Runner-бинарника 0); release-сборка: Frameworks без yuv-ffi.framework, nm -gU Contents/MacOS/yuv_ffi_example -> 0 символов _yuv_*_v1 (в версии с .dynamic символы есть во framework). Решение .dynamic оставлено.
Повторная проверка на Mac (ветка all/STAGE3-SPM-wip, Flutter 3.44.9): bash tool/ci/macos.sh и bash tool/ci/ios.sh проходят в режиме SPM (подробности — в отчёте SPM 3); release-сборка macOS на этом Mac не зависла.
Не запускалось: нет Windows — `pwsh -File tool/ci/example.ps1` не запускался (изменён только example/pubspec.yaml); формальная сверка DoD Reviewer-ом.
(прежняя формулировка:) Не выполнено: example.ps1 после SPM-изменений на Windows не перезапускался (изменён только example/pubspec.yaml); формальная сверка DoD Reviewer-ом.
#### Review
Вердикт: ACCEPTED. Reviewed head: 1a38dd0 (пул STAGE3-SPM целиком, diff `dev...HEAD`).
- DoD сверен с диффом и отчётами Executor: переходники/podspec/Package.swift/заголовок соответствуют решениям карточек; отчёты содержат команды и результаты, согласованы с закоммиченными скриптами (определение режима по Podfile.lock, CocoaPods-проход в копии с pod install заранее, выбор iOS 18.x, git status в macos.sh).
- Windows (Reviewer, из корня worktree): `pwsh -File tool/ci/example.ps1` -> exit 0 (pub get, analyze, build web); `flutter test test/apple_forwarder_sources_test.dart` -> All tests passed (8); `bash -n` scope_guard/ios/macos -> ok; `smoke.ps1` -> exit 0; `vm.ps1` -> 573/573; `dart pub publish --dry-run` -> 0 warnings, darwin/yuv_ffi.podspec, darwin/yuv_ffi/Package.swift, Sources/*.c есть, ios/Classes и macos/Classes и .worktrees/ нет; `git grep ios/Classes|macos/Classes` вне tasks -> пусто.
- Mac не перезапускался: свидетельства конкретны и непротиворечивы. windows/android/web.ps1 не запускались: после зелёных прогонов Executor изменились только example/pubspec.yaml (ключ flutter.config, покрыт example.ps1), example/ios, example/macos, tool/ci/ios.sh|macos.sh и документация.
- Blocking: нет. Advisory: нет.
