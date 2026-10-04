# FIX 8 — Android release-проба обновляет приложение без удаления
**Status:** IN_PROGRESS · **Tier:** T2, Reviewer T2 · **Owner:** Executor · **Depends On:** — · **Probe:** none (только `tool/`; проверка — реальный прогон на Pixel 3 в RELEASE 1)

**Base SHA:** `78eca6c6071004175431f58c27fc8101664d501b`

#### Goal

`tool/probe/run_release_android.ps1` перед установкой выполняет `adb uninstall`. Это удаляет example-приложение с
данными на Pixel 3 и нарушает правило Engineer: обновление на Pixel 3 — только `adb install -r`. Поэтому в RELEASE 1
Reviewer проходил пробу вручную. Удаление понадобилось из-за `--split-per-abi`: Flutter задаёт итоговый
`versionCode = 1000 × код ABI + build number` (armeabi-v7a — 1, arm64-v8a — 2). При одинаковом build number APK armv7
после arm64 получается downgrade, и `install -r` отказывает.

#### Независимый вердикт (04.10.2026)

**Согласен с дефектом и запретом удаления; не согласен с обоими предложенными обходами.** Вариант с минутами Unix
epoch повышает build number лишь на 1 в минуту, тогда как переход arm64 → armv7 уменьшает ABI-слагаемое на 1000.
Быстрый обратный переход по-прежнему даёт downgrade. `adb install -r -d` нарушает точное правило Engineer
«только `adb install -r`» и ненадёжен для release APK на обычной пользовательской сборке Android: downgrade
разрешён лишь для debuggable приложения или debuggable сборки платформы. Подпись debug-ключом не делает release APK
debuggable. Решение ниже использует установленный `versionCode` и сохраняет обычный `install -r`.

#### Architect Decision

Убрать `adb uninstall`, ставить только через `adb install -r`. Перед сборкой прочитать установленный `versionCode`
целевого package на устройстве; если package ещё нет, принять 0. Выбрать `--build-number` так, чтобы итоговый
`versionCode = 1000 × код ABI + build number` был строго больше установленного: например,
`build number = max(1, installedVersionCode + 1 - 1000 × код ABI)`. Если установленный код не удаётся однозначно
прочитать или новый код выходит за допустимый диапазон Android, завершить пробу с диагностикой без установки.
Проверить фактический `versionCode` собранного APK до `adb install -r`; оба числа записать в host evidence.
Ошибка подписи или несовместимости установки — диагностируемый FAIL, без удаления приложения и очистки данных.

#### Scope

`tool/probe/run_release_android.ps1`; при необходимости `test/probe/run_release_android_test.dart` (контракт скрипта).

#### Constraints

- Скрипт не вызывает `adb uninstall`, `pm clear`, `install -d` и любую очистку данных.
- Не меняются: вердикт пробы, разбор logcat, проверка ABI в APK, структура evidence (в host evidence добавляются
  установленный и собранный `versionCode` и `build number`).

#### Definition of Done

- В скрипте нет `uninstall`; установка — только `install -r`, а собранный APK имеет `versionCode` выше установленного.
- Последовательный прогон arm64, затем armv7 (и обратно) на Pixel 3 `8B1X11QLW` проходит без удаления приложения,
  все три вердикта PASS.

#### Validation

- `rg -n 'uninstall|pm clear|install -r -d' tool/probe/run_release_android.ps1` пуст.
- `flutter test --tags release test/probe/run_release_android_test.dart`.
- Проверить вычисление номера для переходов arm64 → armv7 → arm64 с шагом менее минуты, а также отсутствие package,
  ошибку чтения установленного кода и верхнюю границу допустимого `versionCode`.
- Pixel 3: `pwsh -File tool/probe/run_release_android.ps1 -GitSha <HEAD> -Abi arm64`, затем `-Abi armv7`, затем снова
  `-Abi arm64`. Все три — PASS. `adb shell dumpsys package com.example.yuv_ffi_example | rg firstInstallTime` не
  меняется между прогонами: приложение не переустанавливалось.
- Reviewer в RELEASE 1 проходит Pixel 3 этим скриптом.

#### Executor Report

- Удаление заменено на `adb install -r`. Перед сборкой скрипт читает установленный package `versionCode`, рассчитывает
  совместимый `--build-number` для ABI и сверяет реальный APK `versionCode` через `aapt`; host evidence содержит
  установленный и собранный коды и build number.
- Добавлен helper `release_android_versioning.ps1`; контрактные тесты проверяют отсутствие package, ошибку чтения,
  некорректные/предельные значения и быстрый переход arm64 → armv7 → arm64.
- PASS: `flutter test --tags release test/probe/run_release_android_test.dart` — 15 тестов.
- Pixel 3 `8B1X11QLW`, Android 12, точный SHA `fdd1d3f4a00c25e34c04a110f333b8c42eaffdc0`: arm64 PASS
  `13003 → 13004`, armv7 PASS `13004 → 13005`, arm64 PASS `13005 → 13006` (все 1188 cases). Каждый прогон
  использовал `adb install -r`; `firstInstallTime=2026-10-04 13:15:18` до и после серии не изменился.
- `rg -n 'uninstall|pm clear|install -r -d' tool/probe/run_release_android.ps1` — совпадений нет.
- Для каждого прогона использован чистый checkout того же SHA: Flutter build изменяет отслеживаемые Windows plugin
  registrants в validation-клоне; их восстановление между прогонами не затрагивало приложение или данные устройства.

#### Review
