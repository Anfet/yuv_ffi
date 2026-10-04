# FIX 3 — Достоверный CHANGELOG 0.5.0

**Status:** REVIEW · **Tier:** T2, Reviewer T2 · **Owner:** — · **Depends On:** — · **Probe:** none

**Base SHA:** `5a0dcdab5557cf88bc6007658f52a1be5188867c`

#### Goal

Убрать из верхней записи CHANGELOG неверный путь обновления через невыпущенную 0.4.2 и противоречие по удалённому `copy(blank:)`.

#### Architect Decision

1. Раздел «Moving from a 0.4.0 lockfile» должен вести с опубликованной 0.4.0 непосредственно к выпускаемой 0.5.0. Пояснить штатное обновление lockfile приложения без обещания выпуска 0.4.2.
2. Удалить или перенести историческую строку «Clarified that `copy(blank: true)` preserves plane strides» из верхней записи: в 0.5.0 API удалён. Не стирать историю версии 0.4.0.
3. Сверить остальные заявления верхней записи с `COMPLETION.md`, README и кодом. Исправлять только доказанные расхождения; итоговая версия заголовка остаётся `0.5.0-dev.1` до RELEASE 1.

#### Scope

Верхняя запись `CHANGELOG.md`, при необходимости отметка о закрытии находки в `doc/release-0.5.0-audit.md`.

#### Constraints

- Не переписывать записи опубликованных версий и не поднимать D-14 версии.
- Не добавлять утверждения о CI или браузерах без доказательства.

#### Definition of Done

- Миграция из 0.4.0 не отправляет пользователя к 0.4.2; `copy(blank:)` описан только как удалённый API с действующей заменой.
- Утверждения верхней записи согласованы с принятыми пользовательскими изменениями из `COMPLETION.md`.

#### Validation

- `rg -n '0\.4\.2|copy\(blank|^## 0\.5\.0' CHANGELOG.md README.md COMPLETION.md` с разбором каждого совпадения.
- `git diff --check <base>..HEAD`; документационная задача не требует CI или пробы. Отчёт: SHA и список исправленных утверждений.

#### Executor Report

- Base SHA: `5a0dcdab5557cf88bc6007658f52a1be5188867c`; implementation commit: `5d5757bf4e76909ad984c9b6e1bbae850dea62c5`.
- `rg -n '0\.4\.2|copy\(blank|^## 0\.5\.0' CHANGELOG.md README.md COMPLETION.md` — no 0.4.2 migration recommendation remains; README/CHANGELOG current-version mentions describe the removed API and replacement. Remaining matches are historical 0.4.2 cycle notes and the README's storage compatibility fact; the 0.4.0 changelog history is unchanged.
- Compared top-entry highlights and APIs with `COMPLETION.md`, README and `lib/src/yuv/yuv.dart`; no further demonstrated discrepancy found. Lockfile guidance now upgrades directly from 0.4.0 to `^0.5.0`.
- `git diff --check 5a0dcdab5557cf88bc6007658f52a1be5188867c..5d5757bf4e76909ad984c9b6e1bbae850dea62c5` — exit 0. Docs only; no CI/probe required.

#### Review

- **ACCEPT (04.10.2026),** implementation `5d5757b`. Верхняя запись оставлена `0.5.0-dev.1` до RELEASE 1; путь обновления идёт из опубликованной `0.4.0` сразу в `^0.5.0`, а утверждение о сохранении stride удалённым `copy(blank:)` убрано. Историческая запись `0.4.0` сохранена; сверены README, публичный API и `COMPLETION.md`. `git diff --check 5a0dcda..5d5757b` — exit 0; Probe: none.
