# TEST 4 — Карта «что изменил → что запускать»
**Status:** TODO · **Tier:** T3 · **Execution Mode:** FAST · **Review Tier:** T2 · **Depends On:** TEST 2, TEST 3 · **Rejection Count:** 0
**Было:** RA-62 (цикл 0.4.2).

#### Architect Decision
Раздел в `AGENTS.md` проекта — таблица путей и команд, построенная по карте `tool/ci/scope_guard.sh` (RA-53) — какие локальные `tool/ci/<платформа>`-скрипты и команды нужны (по D-9 ветки задач CI не запускают, поэтому карта — основа локальной проверки карточки): `src/**` → `--tags probe,reference` + native CTest; `lib/src/yuv/impl/web/**` → Web-проба; `lib/src/widgets/**` → `contract` + example tests; `*.md` → ничего. Карта путей остаётся в одном источнике — `scope_guard.sh`.
