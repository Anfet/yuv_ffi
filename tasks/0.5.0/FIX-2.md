# FIX 2 — README для финальной версии и границ Web

**Status:** REVIEW · **Tier:** T2, Reviewer T2 · **Owner:** — · **Depends On:** — · **Probe:** none

**Base SHA:** `26028ae1ae0913dea8c90d3ea9373f26e7524ee0`

#### Goal

Сделать установку и Web-ограничения в README точными для выпуска 0.5.0, не выдавая непроверенные браузеры за проверенные.

#### Architect Decision

1. В README дать установку финальной `0.5.0` и убрать формулировку, будто `0.5.0-dev.1` — версия выпуска. Не менять версию в четырёх D-14 файлах: их одновременно повышает RELEASE 1 после закрытия блокирующих находок.
2. В таблице платформ и Web-разделе прямо указать: JavaScript Flutter build проверен в Chrome; Safari и Firefox не проверены; `flutter build web --wasm` не поддерживается при выполнении операций. Требование Safari 16.4+ к release WASM SIMD, если оставлено, описать как технический минимум, не как результат теста этого плагина. Сверить с `doc/web-parity.md`.
3. Проверить пример quick start и таблицу миграции против экспортируемого API. `example/README.md` менять только если в нём обнаружено противоречие по тем же ограничениям.

#### Scope

`README.md`, при необходимости `example/README.md` и ссылка из `doc/release-0.5.0-audit.md` на закрытие находки.

#### Constraints

- Не заявлять паритет Web/native и не добавлять обещание Safari/Firefox.
- Не публиковать пакет, не повышать D-14 версии в этой карточке.

#### Definition of Done

- Команда установки на странице соответствует целевой 0.5.0; все упоминания dev-версии либо удалены, либо явно исторические.
- Web-таблица не смешивает системный минимум с проверенным браузером; `--wasm` и частичность backend согласованы с `doc/web-parity.md`.
- Примеры используют текущий публичный API.

#### Validation

- `rg -n '0\.5\.0-dev\.1|0\.4\.2|Safari|Firefox|Chrome|--wasm' README.md example/README.md doc/web-parity.md` с разбором каждого совпадения.
- Сверка сигнатур quick start и миграционной таблицы с `lib/yuv_ffi.dart` и `lib/src/yuv/yuv.dart`; `git diff --check <base>..HEAD`.
- Документационная задача: CI и пробы не нужны. Результат сверки и SHA — в Executor Report.

#### Executor Report

- Base SHA: `26028ae1ae0913dea8c90d3ea9373f26e7524ee0`; implementation commit: `fad8dda43ebacbc2c103d404e772c6d0f7651535`.
- `rg -n '0\.5\.0-dev\.1|0\.4\.2|Safari|Firefox|Chrome|--wasm' README.md example/README.md doc/web-parity.md` — reviewed all matches; README gives final install version, Chrome JS test status, Safari/Firefox unknown, and `--wasm` runtime limitation. Remaining 0.4.2 references concern historical encoded-frame compatibility.
- Quick start and migration table checked against `lib/yuv_ffi.dart` and `lib/src/yuv/yuv.dart`; referenced factories/methods are public and current. `example/README.md` has no conflicting release/Web claims.
- `git diff --check 26028ae1ae0913dea8c90d3ea9373f26e7524ee0..fad8dda43ebacbc2c103d404e772c6d0f7651535` — exit 0. Docs only; no CI/probe required.

#### Review
