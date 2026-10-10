# YUV 2 — версия 0.5.2 и документы разделения

**Status:** BLOCKED
**Tier:** T2
**Owner:** —
**Depends on:** YUV 1 — принятая очистка примера.
**Probe:** windows+pixel3 — изменяется src/CMakeLists.txt; metadata не освобождает от таблицы Probe.
**Needs:** Pixel 3 (Reviewer).

## Goal

Подготовить YUV 0.5.2 к локальной проверке разделённой пары и этапу кандидатов, согласовав версии и внешние описания.

## Architect Decision

1. Обновить версию вместе в pubspec.yaml, верхней записи CHANGELOG.md, darwin/yuv_ffi.podspec и src/CMakeLists.txt (D-14). Правка CMake только VERSION как metadata; не менять C/ABI/компиляцию и не пересобирать WASM artifacts ради версии.
2. README/example README объясняют разделение и ссылку на yuv_camera. Корневой API геометрии/презентера/шейдера сохраняется; ML Kit callback — пример нового пакета, не зависимость YUV. Внешние тексты и CHANGELOG — английские.
3. По карте 2.6 обновить doc/web-parity.md (исключить camera smoke из YUV-доказательств, сохранить проверенные браузеры/JS/--wasm), указатель в doc/web-camera-yuv.md, устаревшую ссылку в test/pack_planes_native_equivalence_test.dart. Исследование web-camera остаётся основанием perf-findings, не удаляется. Исторический CHANGELOG/COMPLETION не переписывается.
4. Scope_guard учитывает путь src/CMakeLists.txt; metadata не освобождает от его ключей. По проектному правилу src дополнительно выполнить probe/reference и native CTest. Native исходники не менять для прохождения этих проверок. Успешные проверки YUV 1 могут использоваться только для непокрываемых текущими изменениями путей с доказательством diff.
5. Кандидат/CI/device release gate — этап 2, не объявлять готовый выпуск. Карта PREP 1 остаётся источником истории; запись решений и декомпозиция не заменяют независимое ревью PREP.

## Scope

Четыре места версии, README корня/example, doc/web-parity.md, doc/web-camera-yuv.md, комментарий equivalence-теста. todo — состояние этапа, без самоприёмки чужих карточек.

## Constraints

Нет публикации, тегов, release branches, изменения публичного API/алгоритмов или обещаний непроверенных платформ. Не трогать чужие workflows. Версия CHANGELOG и трёх metadata должна совпадать.

## Definition of Done

1. Версия 0.5.2 одна во всех четырёх местах — check: чтение metadata/верхней CHANGELOG записи — by: Executor.
2. Документы соответствуют границе пакетов и Q1–Q4 — check: чтение изменённых разделов против карты 1/2.6/6–7, ссылки корректны — by: Executor.
3. Все обязательные проверки изменённых путей выполнены — check: `bash tool/ci/scope_guard.sh <base>`, соответствующие scripts AGENTS, `flutter test --tags probe`, `flutter test --tags reference`; `cmake -S . -B <temp> -DBUILD_TESTING=ON`, `cmake --build <temp> --config Release`, `ctest --test-dir <temp> -C Release --output-on-failure` — by: Executor.
4. Нет непредусмотренных правок backend или ложных Web-утверждений — check: diff Scope и чтение doc/web-parity — by: Executor.
5. Windows-проба зелёная — check: `pwsh -File tool/ci/windows.ps1`, exit 0, реальные вердикты probe/reference — by: Executor.
6. Pixel 3 проверяет оба ABI, поскольку затронут src — check: на чистом принятом SHA `pwsh -File tool/probe/run_release_android.ps1 -GitSha <полный-SHA> -Serial <Pixel3> -Abi arm64` и та же команда с `-Abi armv7`; exit 0, RA25_RESULT smoke/probe PASS — by: Reviewer.

## Validation

Автоматически вызванные scripts backend-проверки не пропускать. Для Flutter probe/reference подготовить native DLL/PATH существующим _common.ps1. CTest — новый временный каталог вне build; сохранить exit code и короткие логи. git diff --check; Validated at и все результаты в Report. Проверки недоступных remote-платформ конкретно назначить этапу 2, доступные scope-keys обязательны. Pixel3 Reviewer запускает перед приёмкой YUV 2, не откладывает обязательную пробу карточки до выпуска; установить APK только через adb install -r, baseline не менять.

## Executor Report

Заполняет Executor.
