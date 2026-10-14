# Проверки yuv_ffi без CI

Решение Engineer D-38 (10.10.2026, group `todo.md`): GitHub Actions workflows удалены (CI 1), все проверки
запускаются напрямую на собственных машинах. Команды выполняются из корня пакета; машины и доступ —
`D:\.projects\MACHINES.md`. Каталог `tool/ci/` сохраняет прежнее имя как каталог scripts.

## Когда запускать

- **Приёмка карточки:** ключи `bash tool/ci/scope_guard.sh <base>` и `Probe:` карточки (`AGENTS.md`). `all` —
  все ключи таблицы ниже, включая `bindings`.
- **Перед каждым выпуском каждой версии:** весь обязательный набор на чистом закоммиченном кандидате — все ключи ниже,
  полный `flutter test` корня и example, устройства по релизному гейту group `todo.md`. Прежний PASS не заменяет
  прогон; evidence переносится на другой SHA только при пустом diff покрываемых путей (протокол, §5).
- **Отчёт:** полный `Validated at`, машина и SDK, команда, exit code и критерий PASS ниже.

## Native helper cache

`New-CiNativeBuild` хранит build directory под `RUNNER_TEMP` с именем, которое включает имя helper, конфигурацию и
первые 16 hexadecimal символов SHA-256 от нормализованного абсолютного корня checkout. Поэтому два checkout могут
использовать один `RUNNER_TEMP` без CMake source-directory mismatch. Caller всегда добавляет в `PATH` последний
возвращённый helper путь, а не конструирует путь cache самостоятельно. Android helper сохраняет совместимость с
CMake 3.10: linker page-size option передаётся через `LINK_FLAGS`, а native cache по-прежнему разделён по root и
configuration. `smoke.ps1` собирает библиотеку и сверяет возвращённый путь с этим key.

## Бывший workflow / job → script → машина → PASS

Исходные YAML — `.github/workflows/*` на `566e603` (база CI 1). Каждый Windows/Mac workflow только делал checkout,
подготавливал runner и вызывал один script; два inline job из `ci.yml` перенесены шаг в шаг.

| Бывший workflow / job | Шаги | Script | Машина | PASS |
| --- | --- | --- | --- | --- |
| `ci-vm.yml` / `vm` | Git Bash в PATH, Flutter 3.44.9, `tool/ci/vm.ps1` | `pwsh -File tool/ci/vm.ps1` | Windows | exit 0; analyze без ошибок; `smoke \|\| contract` — 0 failed, тестов > 0 (`test_report.dart`) |
| `ci-windows.yml` / `windows-native-smoke` | `tool/ci/windows.ps1` | `pwsh -File tool/ci/windows.ps1` | Windows, VS/CMake | exit 0; `probe` и `reference` — 0 failed; Release-сборка примера; `PASS` app-runtime smoke и каждой цели `*_native_test.dart` на `windows` |
| `ci-android.yml` / `android` | `tool/ci/android.ps1` | `pwsh -File tool/ci/android.ps1` | Windows + Pixel 3 (`ANDROID_SERIAL`) | exit 0; два APK по одной ABI (`arm64-v8a`, `armeabi-v7a`); `PASS` app-runtime smoke и каждой `*_native_test.dart` на serial устройства; установка только `adb install -r`, `firstInstallTime` не меняется; x86_64 не проверяется (D-42) |
| `ci-web.yml` / `web` (self-hosted Mac) | `tool/ci/web.sh` | Windows: `pwsh -File tool/ci/web.ps1`; Mac: `bash tool/ci/web.sh` | Windows (Chrome, ChromeDriver, emsdk 3.1.74); Mac — при проблеме браузерного окружения | exit 0; `pub publish --dry-run` со списком WASM assets; пересборка WASM без diff `assets/wasm`; строки `Web WASM CI passed: targets=3` и `Web CI passed: ... sources=14; integration cases=64; reference matrix=119` |
| `ci-example.yml` / `example-analyze-and-build` | `FLUTTER_VERSION=3.44.9`, `tool/ci/example.ps1` | `FLUTTER_VERSION=3.44.9`, затем `pwsh -File tool/ci/example.ps1` | Windows | exit 0; `Using Flutter 3.44.9`; analyze и `flutter build web` примера |
| `ci-smoke.yml` / `smoke` | `tool/ci/smoke.ps1` | `pwsh -File tool/ci/smoke.ps1` | Windows | exit 0; `CI helper smoke passed.` |
| `ci-macos.yml` / `macos-native-smoke` | `tool/ci/macos.sh` | `bash tool/ci/macos.sh` | Mac | exit 0; packaging smoke; Release-сборка через SwiftPM; `PASS` app-runtime smoke и каждой `*_native_test.dart` на `macos`; CocoaPods-копия; tracked-файлы не изменены |
| `ci-ios.yml` / `ios-native-build` | `tool/ci/ios.sh` | `bash tool/ci/ios.sh` | Mac, Xcode и симулятор iOS 18.x | exit 0; `PASS` app-runtime smoke и каждой `*_native_test.dart` на симуляторе; app-runtime smoke CocoaPods-копии |
| bindings audit/regeneration | libclang из Xcode; `pub get`; ffigen; `verify_bindings_audit.dart`; сравнение с исходными файлами | `bash tool/ci/bindings.sh` в чистой копии точного коммита | Mac, Xcode | exit 0; `AUDIT` без ошибок (`SUCCESS`); оба `git diff --no-index` против исходных `ffigen.yaml` и `yuv_ffi_bingings.dart` — exit 0; строка `Bindings check passed` |
| `ci.yml` / `linux-native-smoke` (`ubuntu-latest`) | `pub get`; версии clang/cmake; CTest Debug и Release с `BUILD_TESTING=ON`, clang; число sanitizer cases; сборка `libyuv_ffi.so`; packaging smoke через `LD_LIBRARY_PATH`; `flutter create --platforms=linux`, восстановление и проверка `pubspec.lock`, `flutter build linux --release`; app-runtime smoke; все `*_native_test.dart` через `xvfb-run` | `bash tool/ci/linux.sh` | Ubuntu VM 24.04: clang, cmake, ninja, GTK 3, xvfb (пакеты ставит Engineer, script ничего не устанавливает) | exit 0; оба CTest без провалов; `abi_sanitizer_test`: `failures: 0`, cases > 0 и без `SKIPPED` (malloc `--wrap` выполнен); packaging smoke 0 failed; lock без drift; `PASS` app-runtime smoke и каждой native-цели; пустой набор целей — FAIL; итоговая строка `Linux checks passed` |

Отличия от прежних job: `linux.sh` собирает и запускает пример в копии кандидата во временном каталоге (checkout не
меняется, `example/linux` не создаётся в checkout), CMake-каталоги — там же; `LD_LIBRARY_PATH` задаётся только для
packaging smoke, поэтому app-runtime и native-цели находят библиотеку только через install rules плагина.
`bindings.sh` сравнивает результат с копиями исходных файлов, сохранёнными до генерации, и работает и в
`git archive`-копии без `.git`; в git checkout с изменёнными tracked-файлами он останавливается.

## Наборы integration targets

Набор native-целей определяется glob `example/integration_test/*_native_test.dart` во всех платформенных scripts
(`windows.ps1`, `android.ps1`, `macos.sh`, `ios.sh`, `linux.sh`); на базе CI 1 это `presenter_shader_native_test.dart`,
`probe_native_test.dart`, `shader_probe_native_test.dart`, плюс отдельный `native_app_runtime_smoke_test.dart`.
Web-цели и их число проверяет `Assert-WebSourceMatrix` в `web.ps1` (и аналог в `web.sh`): актуальная матрица после FIX 11 — 14 источников и 65 integration cases. Указанные выше числа из CI 1 относятся к исторической базе и не являются текущим результатом проверки.

## Что script не доказывает

Сборка, эмулятор, симулятор и fake-устройства не подтверждают физические устройства: Pixel 3 и iPhone проверяются
отдельными задачами релизного гейта. Безголовый Chrome на Windows не подтверждает Safari и Firefox (D-27).

Debug-прогон `android.ps1` на Pixel 3 не заменяет release-пробу DEVICE 1: runtime `armeabi-v7a` и скорость подтверждаются только там.
