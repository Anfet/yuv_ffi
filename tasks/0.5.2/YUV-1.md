# YUV 1 — удалить перенесённую камеру из примера

**Status:** BLOCKED
**Tier:** T2
**Owner:** —
**Depends on:** yuv_camera: CAM 3 — принятый G1 с 34/34 и native/Web capture.
**Probe:** none — example, tests, scripts и платформенная конфигурация; операции lib/src не меняются.

## Goal

Сделать пример YUV независимым от камеры и ML Kit после доказанного сохранения камерного покрытия в новом пакете.

## Architect Decision

1. Перед удалением прочитать Report CAM 3 в `D:\.projects\yuv_ffi_camera\tasks\0.0.1\CAM-3.md` (после DONE — COMPLETION и git history). Проверить G1 PASS, 34/34, приёмку. Число файлов само по себе не подтверждает перенос assertions. На старте записать базовый SHA dev этого репозитория.
2. Удалить только строки «перенести» из карты 2.1–2.3. Редактор сохранить: загрузка/операции/Reset/YuvFrameView; убрать face detection, Take photo, Device check и камерные импорты. Сценарий C5 (crop+negate+Reset) сохранить в editor_screen_test, не оставлять интеграционный файл с камерным названием в YUV.
3. Удалить camera, camera_desktop, camera_platform_interface, ML Kit и web из example/pubspec. ffi удалить только после rg подтверждения отсутствия использования. Crypto/image/helpers/операционные probes и synthetic-stream tests сохранить. Locks/registrants пересоздать инструментами, не редактировать вручную.
4. Удалить только камерные permissions/entitlements/настройки из карты 2.5. iOS deployment 15.5 и simulator 18.x сохранить: их снижение отдельная работа. CocoaPods regenerates на Mac при платформенной проверке, не имитировать правкой lock.
5. В том же изменении убрать вызов camera Web smoke и его итоговое число из web.ps1/web.sh; удалить Linux GStreamer install/VIEW-01A из ci.yml. Нативный glob не менять: остаются три YUV *_native_test targets. Не переписывать посторонние текущие изменения workflows.
6. Для editor unit-теста native DLL нужна в PATH: собрать через существующий `New-CiNativeBuild` (_common.ps1) во временном каталоге, добавить возвращённый каталог в PATH процесса; из example запустить `flutter test test/editor/editor_screen_test.dart`. Не добавлять собственный CMake-проект и не менять src.

## Scope

Перечисленные пути example/lib, test, integration_test и pubspec/platforms; web.* и Linux workflow — карта 2.1–2.6. Не менять библиотеку YUV и её публичные exports.

## Constraints

Удаление только после принятого G1. Native C/WASM/assets probes/public API YUV не меняются. Не снижать платформенные требования, не удалять синтетические/операционные тесты, не запускать физический iPhone.

## Definition of Done

1. Камера/ML Kit отсутствуют в коде и прямых зависимостях примера — check: `rg -n -i 'package:(camera|camera_desktop|camera_platform_interface|google_mlkit)|YuvCamera|DeviceCheck|detectFace' example/lib example/test example/integration_test` без совпадений; чтение pubspec и registrants — by: Executor.
2. C5 и старое утверждение editor сохранены — check: `flutter test test/editor/editor_screen_test.dart` из example с native DLL в PATH, все cases PASS; чтение против карты 3.2 — by: Executor.
3. Scripts не ссылаются на удалённые камерные targets, сохранились YUV targets и матрицы — check: rg/read web scripts и ci.yml против карты 2.6 — by: Executor.
4. Проверки scope завершились успешно — check: `bash tool/ci/scope_guard.sh <base>` и команды по выведенным ключам из AGENTS; Windows-local vm/windows/android/web/example/smoke, для example задать FLUTTER_VERSION=3.44.9 — by: Executor.
5. Остальные платформы явно переданы этапу 2, если недоступны локально; доступные обязательные проверки не пропущены — check: Report с ключами, exit code, результатами и ресурсами — by: Executor.

## Validation

Scope ожидается all из-за integration_test/scripts; источник правды — scope_guard. Проверки выполняются локальными scripts; build/drive напрямую не подменяют их. Probe none не отменяет script-checks. Формат touched Dart, targeted analyze и git diff --check. Backend probes, вызываемые scripts, пишут реальные вердикты; FAIL не сдаётся. Mac/Linux/device checks всех кандидатов — этап 2; недоступность обязательного Windows-local ресурса требует BLOCKED. Validated at и G1-ссылка обязательны.

## Executor Report

Заполняет Executor.
