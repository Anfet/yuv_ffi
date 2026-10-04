# FIX 10 — Форматирование `lib/` под pana 160/160
**Status:** TODO · **Tier:** T2, Reviewer T2 · **Owner:** — · **Depends On:** — · **Probe:** none (только форматирование, байткод не меняется)
**Base SHA:** `df14dc8e5d42d9330d4bfa8592194a52d3a09556`

#### Goal
`pana` на кандидате `df14dc8` дал 150/160: три файла `lib/` не прошли `dart format` (40/50 в «Pass static analysis»).
DoD RELEASE 1 требует 160/160.

#### Architect Decision (draft, решение Engineer: нужен новый SHA РК и полный повтор RELEASE 1, п. 3–4)
1. `dart format --line-length 150` (page_width из `analysis_options.yaml`) для `lib/src/yuv/impl/io/yuv_image.dart`,
   `lib/src/yuv/impl/web/yuv_web.dart`, `lib/src/yuv/impl/yuv_stub.dart`. Других правок нет.
2. Рекомендуется заодно отформатировать два файла example (`example/integration_test/padded_bgra_constructor_web_test.dart`,
   `example/lib/device_check/device_check_screen.dart`) — pana их не считает, но `dart format --set-exit-if-changed .` станет чистым.
3. Проверка: `dart format --output=none --set-exit-if-changed .` — exit 0; `git diff -w` не показывает значимых изменений;
   `flutter analyze` чистый; `vm.ps1`. Затем `release/0.5.0` → новый SHA, RELEASE 1 повторяется целиком (CI тег `-v4`).

#### Executor Report

#### Review
