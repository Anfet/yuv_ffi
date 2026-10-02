# CLEAN 4 — Документация и комментарии по стандартам pub.dev
**Status:** BLOCKED · **Tier:** T2 · **Owner:** CLEAN 3 · **Depends On:** CLEAN 3

#### Goal
Привести публикуемый пакет к обычному виду пакета pub.dev: README, CHANGELOG, `example/README.md`, dartdoc
публичного API и комментарии в коде (`lib/`, `src/`, `darwin/`, `example/lib/`) — без внутреннего шума. Что уже
видно при постановке:

- в комментариях кода остались внутренние ID задач (`PACK-01D`, `RA-25` и т. п., около 10 мест) и рассуждения
  о процессе — им место в git, не в коде;
- комментарии, пересказывающие следующую строку, и длинные «истории» вместо причины;
- dartdoc публичного API не проверяется: нет `public_member_api_docs`, `dart doc` не прогоняется;
- `.pubignore` перечисляет давно удалённые файлы; `doc/archive/` закоммичен (9 файлов), хотя история — в git
  (`AGENTS.md`, «История задач»);
- оценка `pana` и `dart pub publish --dry-run` не снимались.

Эталон проверки — `pana` (оценка и замечания), `dart pub publish --dry-run` без предупреждений, `dart doc` без
предупреждений. Поведение кода не меняется; `lib/src/functions/bindings/` (сгенерированный) не трогать.

Этап 6, после CLEAN 3 (чтобы убирать уже переработанный example).

#### Architect Decision
Черновик. При входе в этап Architect дописывает: правило комментария (что остаётся, что уходит — по глобальному
`CODESTYLE.md`), список документов и разделов README, включать ли `public_member_api_docs`, что делать с
`doc/archive/` и `doc/*.md`, Probe (комментарии в `lib/src/yuv/impl/**` и `src/` формально дают `windows+pixel3`).

#### Scope
#### Constraints
#### Definition of Done
#### Validation
#### Executor Report
#### Review
