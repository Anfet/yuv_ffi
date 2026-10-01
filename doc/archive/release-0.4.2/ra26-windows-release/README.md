# PROBE 1 — release baseline 0.4.0 against dev

## Контур

- Windows: `13th Gen Intel(R) Core(TM) i9-13980HX`, x64, release, Balanced
  (`381b4222-f694-41f0-9685-ff5bb260df2e`), external AC.
- Android: Pixel 3 (`8B1X11QLW`), arm64-v8a, release; экран включён,
  keyguard снят, `mWakefulness=Awake`, thermal status `0`.
- Tag package: `0.4.0` (`d5d78eb04cf0b276dbc0a1ba869cd7152daab8f9`).
- HEAD package: Windows `202c03b82347b2fb4895fd416b01935f33036d77`, Pixel
  `325d6da3171905d814e1d28119ed660eea85541f`; разница между этими двумя
  revision только в host runner и его contract tests, не в public/native code.

Каждая строка — медиана девяти AOT вызовов в миллисекундах. Все 24 результата
на обеих платформах имеют стабильный post-timer hash. `SAME` сохраняет
измеренную разницу, когда она не превысила `max(15%, 2 × spread)`.

| Operation / scenario / size | Windows 0.4.0 → HEAD | Pixel 3 0.4.0 → HEAD |
| --- | ---: | ---: |
| convert / i420-to-bgra / 1920×1080 | 184.813 → 36.015 (−80.5%, FASTER) | 101.372 → 26.679 (−73.7%, FASTER) |
| convert / i420-to-bgra / 720×360 | 24.661 → 5.818 (−76.4%, FASTER) | 12.275 → 3.024 (−75.4%, FASTER) |
| blackWhite / i420-whole-frame / 1920×1080 | 434.432 → 48.381 (−88.9%, FASTER) | 198.097 → 45.568 (−77.0%, FASTER) |
| blackWhite / i420-whole-frame / 720×360 | 58.112 → 6.415 (−89.0%, FASTER) | 24.150 → 5.315 (−78.0%, FASTER) |
| grayscale / i420-whole-frame / 1920×1080 | 420.103 → 48.846 (−88.4%, FASTER) | 193.818 → 45.185 (−76.7%, FASTER) |
| grayscale / i420-whole-frame / 720×360 | 52.444 → 5.824 (−88.9%, FASTER) | 23.715 → 5.204 (−78.1%, FASTER) |
| negate / i420-whole-frame / 1920×1080 | 428.281 → 47.301 (−89.0%, FASTER) | 168.713 → 39.562 (−76.6%, FASTER) |
| negate / i420-whole-frame / 720×360 | 52.931 → 5.526 (−89.6%, FASTER) | 20.748 → 4.589 (−77.9%, FASTER) |
| gaussianBlur / i420-r3-s2 / 1920×1080 | 1118.485 → 406.217 (−63.7%, FASTER) | 692.228 → 286.475 (−58.6%, FASTER) |
| gaussianBlur / i420-r3-s2 / 720×360 | 137.962 → 49.491 (−64.1%, FASTER) | 86.057 → 34.456 (−60.0%, FASTER) |
| meanBlur / i420-r2 / 1920×1080 | 528.489 → 101.677 (−80.8%, FASTER) | 351.570 → 69.808 (−80.1%, FASTER) |
| meanBlur / i420-r2 / 720×360 | 66.054 → 11.918 (−82.0%, FASTER) | 42.737 → 8.338 (−80.5%, FASTER) |
| boxBlur / i420-r2 / 1920×1080 | 529.534 → 100.929 (−80.9%, FASTER) | 349.249 → 70.048 (−79.9%, FASTER) |
| boxBlur / i420-r2 / 720×360 | 64.160 → 12.175 (−81.0%, FASTER) | 43.141 → 8.348 (−80.6%, FASTER) |
| crop / i420-inset-8 / 1920×1080 | 110.766 → 8.937 (−91.9%, SAME) | 56.054 → 9.772 (−82.6%, SAME) |
| crop / i420-inset-8 / 720×360 | 13.021 → 0.876 (−93.3%, SAME) | 5.795 → 0.311 (−94.6%, SAME) |
| flipHorizontal / i420-whole-frame / 1920×1080 | 114.747 → 14.442 (−87.4%, FASTER) | 54.338 → 13.375 (−75.4%, FASTER) |
| flipHorizontal / i420-whole-frame / 720×360 | 13.919 → 1.622 (−88.3%, FASTER) | 6.356 → 1.302 (−79.5%, FASTER) |
| flipVertical / i420-whole-frame / 1920×1080 | 112.129 → 7.661 (−93.2%, SAME) | 52.487 → 6.287 (−88.0%, SAME) |
| flipVertical / i420-whole-frame / 720×360 | 13.878 → 0.869 (−93.7%, FASTER) | 6.179 → 0.369 (−94.0%, FASTER) |
| rotate / i420-90 / 1920×1080 | 117.067 → 19.911 (−83.0%, FASTER) | 57.065 → 27.045 (−52.6%, FASTER) |
| rotate / i420-90 / 720×360 | 15.019 → 2.044 (−86.4%, FASTER) | 6.304 → 2.643 (−58.1%, FASTER) |
| chromaSwap / nv12-whole-frame / 1920×1080 | 89.846 → 9.024 (−90.0%, FASTER) | 44.411 → 6.983 (−84.3%, SAME) |
| chromaSwap / nv12-whole-frame / 720×360 | 10.798 → 0.868 (−92.0%, SAME) | 4.977 → 0.293 (−94.1%, SAME) |

Повторный Windows HEAD run против первого HEAD дал 24/24 `SAME`. Raw verdicts
и hashes находятся в `raw/`; versioned Windows tag baseline — в
`test/probe/baseline/windows-13th-gen-intel-r-core-tm-i9-13980hx-x64-release.json`.
