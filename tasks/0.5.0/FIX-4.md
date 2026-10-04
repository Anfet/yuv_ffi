# FIX 4 — Синхронизация lockfile example с версией релиза
**Status:** DONE · **Tier:** T1, Reviewer T1 · **Owner:** — · **Depends On:** FIX 1–3 (DONE) · **Probe:** none

**Base SHA:** 6f878ce9d2177e5ad7a21b5e47eeb72d9273496d

#### Goal

Устранить два падения релизного CI, вызванных устаревшей версией локального пакета в `example/pubspec.lock`.

#### Architect Decision

Engineer в ответе на ревью RELEASE 1 указал на правильную версию `0.5.0`. Обновить lockfile штатным `flutter pub get` в `example/`, принять только изменение версии path-зависимости `yuv_ffi` с `0.5.0-dev.1` на `0.5.0`. Код и другие зависимости не менять. После принятия FIX 4 создать новый SHA релиз-кандидата и повторить упавшие релизные проверки.

#### Scope

`example/pubspec.lock`, верхняя запись `CHANGELOG.md`, эта карточка и статус в `todo.md`.

#### Definition of Done

- В lockfile версия `yuv_ffi` равна `0.5.0`, как в `pubspec.yaml`.
- Повторный `flutter pub get` не меняет lockfile.
- `tool/ci/example.ps1` проходит.

#### Validation

Executor: повторный `flutter pub get` в `example/`, diff lockfile, `pwsh -File tool/ci/example.ps1`; Reviewer: сверить единственную правку lockfile и повторить разрешение зависимостей на чистом SHA.

#### Executor Report

**STATUS: REVIEW.** `flutter pub get` в `example/` изменил только `yuv_ffi` `0.5.0-dev.1` → `0.5.0`. Повторный запуск — exit 0, `Got dependencies!`, новых изменений нет. `$env:FLUTTER_VERSION='3.44.9'; pwsh -File tool/ci/example.ps1` — exit 0: pub get, analyze, release Web build прошли. Релизный CI и Pixel 3 на новом SHA ещё не запускались; они относятся к RELEASE 1 после принятия FIX 4.

#### Review

- **ACCEPT (04.10.2026),** SHA `0be7bcb`. Диапазон `6f878ce..0be7bcb`: в `example/pubspec.lock` единственная правка — path-зависимость `yuv_ffi` `0.5.0-dev.1` → `0.5.0`, совпадает с `pubspec.yaml`; других lockfile в репозитории нет, `0.5.0-dev` вне истории не осталось. Независимо на чистом дереве, Flutter 3.44.9: `flutter pub get` в `example/` — `Got dependencies!`, lockfile не изменился; `FLUTTER_VERSION=3.44.9 pwsh -File tool/ci/example.ps1` — exit 0 (pub get, analyze, build web); `pwsh -File tool/ci/vm.ps1` — exit 0, 635/635, 0 skip, после него `git status` чистый (в ревью RELEASE 1 этот прогон менял lockfile). Linux и macOS CI подтверждаются только на новом SHA РК в RELEASE 1. Замечание без блокировки: строка в CHANGELOG описывает внутреннюю правку example, а не изменение пакета; её можно убрать при подготовке РК.
