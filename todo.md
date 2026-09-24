# yuv_ffi 0.4.1 — открытые задачи

Версия 0.4.0 уже опубликована; этот список относится к последующей работе. Ветка `release/0.4.1` создана, но версия пакета остаётся 0.4.0 до отдельной подготовки выпуска. AUD-02 и AUD-03 приняты; AUD-01 возвращена на доработку после ревью.

## AUD-01 — Проверить заявленную нижнюю границу SDK

- Статус: TODO — analyzer и тесты в CI проходят, но часть legacy-контрактов подменена другими проверками; приоритет: P1; исполнитель: GPT-5.6 Terra; независимая приёмка: GPT-6 Sol.
- Исходный факт: `pubspec.yaml` требует Dart `^3.10.0` и Flutter `>=3.38.0`. На Mac с Flutter 3.38.10 / Dart 3.10.9 до исправления `flutter analyze` пакета выдавал 794 `info` и завершался с кодом 1; errors/warnings не было.
- Готово, когда: на Flutter 3.38.x воспроизводимо проходят согласованный штатный analyzer-gate и тесты пакета; минимальная версия добавлена в CI; намеренные legacy-проверки сохранены, а подавление диагностик адресное и объяснено.
- Сделано: глобальное подавление `deprecated_member_use_from_same_package` удалено из `analysis_options.yaml`; оставшиеся обращения подавляются адресными строковыми комментариями. `flutter analyze` на Flutter 3.38.10 / Dart 3.10.9: `No issues found`. CI matrix с 3.38.10 добавлена в `772f20a`. Затронутые файлы отформатированы; DartDoc больше не разрывается комментариями подавления. Часть обычных тестов переведена на актуальный API. В текущем дереве 672 строковых подавления `deprecated_member_use_from_same_package` (после последующих исправлений legacy-тестов), поэтому прежнее число 647 больше не актуально.
- CI-проверка 2026-09-24: после исправления четырёх оставшихся native-contract тестов в `68a85f9`, GitHub Actions run 36018331214 успешно завершил `analyze-and-test-vm (3.38.10)` и `analyze-and-test-vm (3.44.9)`. Это подтверждает прохождение analyzer и выполнение текущих тестов на заявленной нижней версии Flutter; полнота legacy-проверок требует доработки ниже.
- Ревью 2026-09-24: в `test/conversions_test.dart` тест «NV21 round-trip» (строка 207) создаёт `YuvImage.nv12`; тест сравнения специализированного и общего BGRA-конструкторов (строка 537) оставил в цикле только специализированный; проверка `copy(blank: true)` для padded layout (строка 561) заменена проверкой `YuvImage.allocate`, которая не проверяет сохранение padding; группа «getBytes contract» (строка 587) проверяет `toBytes()`. Зелёный CI не подтверждает эти заявленные legacy-контракты. Требуется вернуть их проверки с адресными подавлениями или явно перенести эквивалентное покрытие в отдельные тесты, а изменённые тесты переименовать по фактическому API. После этого повторить analyzer и VM matrix.

## AUD-02 — Устранить сбой первой iOS Simulator сборки

- Статус: DONE — cold iOS simulator путь и CI-приёмка подтверждены; приоритет: P1; исполнитель: GPT-5.6 Terra; независимая приёмка: GPT-6 Sol.
- Исходный факт: на двух независимых чистых Mac checkout первый `flutter drive` на iPhone 16 Pro Simulator (iOS 18.6) завершился `Framework 'Pods_Runner' not found` под Flutter 3.38.10 и 3.44.9 соответственно. Повторная сборка, затем runtime smoke прошли на обеих версиях; тест подтвердил реальную конверсию и эффект.
- Готово, когда: причина холодного сбоя установлена; первая сборка и `integration_test/native_app_runtime_smoke_test.dart` проходят из нового checkout без ручного повтора; симуляторный smoke включён в CI. Не считать успешный повтор доказательством исправления холодного старта.
- Сделано: обновлён `Podfile.lock` (`ae5eeff`); simulator route в CI перенесён перед unsigned device build. Повторная приёмка выполнена в новом clone `/private/tmp/yuv-ffi-aud02.ySD1fm` на `cf83a2a`: `flutter pub get → pod install → boot simulator → Pods-Runner → flutter build ios --simulator → native_app_runtime_smoke_test → flutter build ios --debug --no-codesign`. Runtime smoke напечатал `YUV-06 app-runtime smoke passed on ios` и `All tests passed`; device build завершился успешно.
- Приёмка 2026-09-24: iOS CI job run 36015478340 завершился успешно на commit `5a3e3ec`. Он прошёл `Install iOS pods → Boot simulator → Build Pods-Runner → Build example (ios simulator) → App-runtime smoke (ios simulator) → Build example (ios device)`. Это подтверждает cold путь и фактическое исполнение simulator smoke до device build.

## AUD-03 — Проверить полный iOS example на физическом устройстве

- Статус: DONE — искажение закрыто воспроизводимым pixel-эталоном и физическим iPhone-прогоном; приоритет: P1; исполнитель: GPT-5.6 Terra; независимая приёмка: GPT-6 Sol.
- Факт: `example/integration_test/example_camera_flow_test.dart` покрывает захват кадра, face detection, crop и эффект, но не запускается в CI. Симуляторный smoke из AUD-02 проверяет только нативную библиотеку, не камеру/ML Kit.
- Готово, когда: test-сценарий пройдёт на сопряжённом iPhone без пропусков с логом и доступом к камере, положительный результат face detection будет подтверждён на кадре с лицом, а BGRA layout и отображение захваченного кадра будут проверены.
- Ранние запуски из удалённой сессии устанавливали приложение, но не подключались к Dart VM (`SocketException ... 0.0.0.0:5353`); это не было camera-flow verdict. В persistent interactive terminal-сеансе физический запуск подключился к VM и исполнил тест.
- Сделано на сопряжённом `Oleg’s iPhone` (iOS 18.7.8) с Flutter 3.38.10: signed build, установка, capture, положительный ML Kit face detection, crop и negate завершились за 6 секунд с `All tests passed`. Тест ждёт публикации кадра после возврата с camera route, требует `faceBox != null`, проверяет BGRA format и `pixelStride == 4`; `flutter analyze` для `example/` чист.
- Приёмка после ревью: добавлен `example/integration_test/ios_bgra_camera_frame_test.dart` — на iPhone он создаёт iOS `kCVPixelFormatType_32BGRA` fixture 2×2 с `bytesPerPixel: null`, padding в каждой строке и уникальными пикселями. После `CameraImageExt.toYuvImage()` он требует `pixelStride == 4`, исходный `rowStride == 12` и точный tight-BGRA массив без padding. Physical `flutter drive` на `00008030-001C6D960AC0202E` завершился успешно. Это непосредственно проверяет отсутствие сдвига строк/пикселей, который давал видимое искажение.
- Независимая перепроверка 2026-09-24: оба теста запущены на подключённом iPhone с текущими файлами и завершились с кодом 0: BGRA pixel-эталон — `All tests passed`; полный camera-flow — `All tests passed`, ML Kit обнаружил лицо, crop и negate исполнились. Эталон подтверждает правильную укладку пикселей для проверенного BGRA layout; визуальный осмотр произвольных живых кадров в этот автоматический тест не входит.

## AUD-04 — Согласовать README с фактической матрицей проверок

- Статус: TODO; приоритет: P2; исполнитель: GPT-6 Luna; независимая приёмка: GPT-6 Sol.
- Факт: README уже содержит API/миграцию 0.4.0, но Web-parity matrix ссылается на `test/web/wasm_parity_*`, которые в обычном VM-прогоне заменяются skip-заглушками; реальный WASM gate находится в `example/integration_test/*`. Фраза о том, что Web reference matrix ещё «will run», устарела. Платформенный раздел пока говорит только об iOS build; дизайн 0.4.0 ссылается на прежнюю историю в `todo.md`, которая удалена из активного трекера.
- Готово, когда: README/дизайн описывают текущие CI targets, фактический iOS smoke и границы Web без заявления о полной parity; команды проверки и ссылки ведут к существующим файлам; версия 0.4.0 и ограничения остаются точными.

## AUD-05 — Добавить Android app-runtime проверку

- Статус: TODO; приоритет: P2; исполнитель: GPT-5.6 Terra; независимая приёмка: GPT-6 Sol.
- Факт: `android-native-build` собирает example APK, но не запускает приложение и ABI smoke на Android. В отличие от Linux/macOS, Android runtime сейчас не подтверждён CI.
- Готово, когда: на Android emulator или устройстве выполнен тест загрузки библиотеки, конверсии и эффекта без skip; результат и используемый ABI отражены в CI/README.
