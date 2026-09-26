# Предрелизные задачи yuv_ffi 0.4.2

## Проверки по платформам

Одна и та же чистая финальная ревизия должна пройти проверки ниже. Существующие CI jobs уже покрывают Android emulator, Linux/macOS desktop, iOS Simulator и браузерный WASM; задача — подтвердить на финальном SHA именно изменённые конвертации и blur, включая реальные loader/asset пути. Web остаётся частичным WASM backend. Отсутствие локальной Linux машины закрывается hosted CI, а не предположением по Windows.

| ID | Статус | Исполнитель | Проверка и артефакт |
| --- | --- | --- | --- |
| PRE-00 | TODO | T1 · GPT-6 Sol; исполнение теста T2 · GPT-5.6 Terra | Подготовить маленький общий app-runtime smoke для оптимизированных NV12/I420/BGRA конвертаций и box/mean/Gaussian, с фиксированными входами/checksum, odd geometry и padded row. Встроить в существующие platform jobs без полной новой матрицы; Web использует собственный browser runner. |
| PRE-01 | TODO | T2 · GPT-5.6 Terra; проверка T1 · GPT-6 Sol | Android: Pixel 3 arm64 Release/AOT на 720×360 и эталонном кадре, результат/время/checksum для конвертаций и blur; проверить фактический порядок chroma CameraX по байтам. Привязать к тому же SHA зелёные CI x86_64 и ARMv7 runtime jobs. |
| PRE-02 | TODO | T2 · GPT-5.6 Terra; проверка T1 · GPT-6 Sol | Windows x64 Release: `flutter test` native/contract, примерное приложение и app-runtime smoke, 12 конвертаций/blur, padding/ROI. Сохранить версию toolchain, SHA, raw время и checksum; при возможности добавить отсутствующий Windows CI job. |
| PRE-03 | TODO | T2 · GPT-5.6 Terra; проверка T1 · GPT-6 Sol | macOS desktop: чистая CocoaPods/Xcode сборка, `flutter drive` с реальным process-linked plugin без side-loaded dylib, адресные конвертации/blur и loader smoke. Записать архитектуру Mac runner и ссылку на CI job; отдельно проверить cold build. |
| PRE-04 | TODO | T2 · GPT-5.6 Terra; проверка T1 · GPT-6 Sol | Web: пересобрать WASM asset из финального C, запустить Chrome `flutter drive` с asset bundle, имеющиеся reference 119 cases и адресные новые сценарии. Фиксировать поддерживаемые операции и расхождения с native как ограничения частичного backend. |
| PRE-05 | TODO | T2 · GPT-5.6 Terra; проверка T1 · GPT-6 Sol | Linux x64 через hosted CI: чистая Release сборка `.so` и example, `native_packaging_smoke_test.dart`, `xvfb-run flutter drive` и PRE-00. Сохранить ссылку на зелёный run именно финального SHA; локальная Linux машина не требуется. |
| PRE-06 | TODO | T2 · GPT-5.6 Terra; проверка T1 · GPT-6 Sol | iOS как объявленная шестая платформа: чистая сборка pod/Simulator, `flutter drive` app-runtime smoke и PRE-00, checksum/архитектура/CI run. Физическое устройство проверить при наличии, не подменяя его симулятором в отчёте. |
| PRE-07 | TODO | T1 · GPT-6 Sol; проверка T2 · GPT-5.6 Terra | После platform gates сверить `CHANGELOG.md`/`pubspec.yaml`, выполнить корневой анализ/тесты, native sanitizers и `flutter pub publish --dry-run` на одном чистом финальном SHA. Свести ссылки на все runs и оставшиеся ограничения до решения о релизе; ничего не публиковать этой задачей. |
