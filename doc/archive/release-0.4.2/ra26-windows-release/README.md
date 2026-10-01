# PROBE 1 — release baseline 0.4.0 against dev

## Контур

- Windows: `13th Gen Intel(R) Core(TM) i9-13980HX`, x64, AOT Release, Balanced (`381b4222-f694-41f0-9685-ff5bb260df2e`), AC online before and after every run.
- Windows app commit: `3c0011f1c88481af9d241be26a75dd7194f1d3a4`; tag package: `d5d78eb04cf0b276dbc0a1ba869cd7152daab8f9`; HEAD package: `3c0011f1c88481af9d241be26a75dd7194f1d3a4`.
- Each Windows verdict has a same-run `*-host.json` receipt linked by `runId` and verdict SHA-256; it records the actual `package_config.json` entry/root, revision and override state, EXE/DLL hashes, CPU/host ID, and observed power readings.
- Android Pixel 3 evidence remains the accepted previous evidence; its benchmark source and measured package behavior did not change.

Каждая строка — медиана девяти AOT вызовов в миллисекундах. Во всех Windows verdicts 24 unique IDs и стабильные post-timer hashes. HEAD repeat дал 24/24 `SAME`.

| Operation / scenario / size | Windows 0.4.0 → HEAD | Pixel 3 0.4.0 → HEAD |
| --- | ---: | ---: |
| convert/i420-to-bgra/1920x1080 | 191.715 → 36.926 (-80,7%, FASTER) | 101.372 → 26.679 (-73,7%, FASTER) |
| convert/i420-to-bgra/720x360 | 26.184 → 5.554 (-78,8%, FASTER) | 12.275 → 3.024 (-75,4%, FASTER) |
| blackWhite/i420-whole-frame/1920x1080 | 424.011 → 48.036 (-88,7%, FASTER) | 198.097 → 45.568 (-77,0%, FASTER) |
| blackWhite/i420-whole-frame/720x360 | 53.050 → 6.299 (-88,1%, FASTER) | 24.150 → 5.315 (-78,0%, FASTER) |
| grayscale/i420-whole-frame/1920x1080 | 426.057 → 47.962 (-88,7%, FASTER) | 193.818 → 45.185 (-76,7%, FASTER) |
| grayscale/i420-whole-frame/720x360 | 52.333 → 5.753 (-89,0%, FASTER) | 23.715 → 5.204 (-78,1%, FASTER) |
| negate/i420-whole-frame/1920x1080 | 413.064 → 44.019 (-89,3%, FASTER) | 168.713 → 39.562 (-76,6%, FASTER) |
| negate/i420-whole-frame/720x360 | 51.673 → 5.613 (-89,1%, FASTER) | 20.748 → 4.589 (-77,9%, FASTER) |
| gaussianBlur/i420-r3-s2/1920x1080 | 1100.098 → 393.820 (-64,2%, FASTER) | 692.228 → 286.475 (-58,6%, FASTER) |
| gaussianBlur/i420-r3-s2/720x360 | 141.172 → 49.162 (-65,2%, FASTER) | 86.057 → 34.456 (-60,0%, FASTER) |
| meanBlur/i420-r2/1920x1080 | 521.018 → 97.988 (-81,2%, FASTER) | 351.570 → 69.808 (-80,1%, FASTER) |
| meanBlur/i420-r2/720x360 | 64.107 → 12.326 (-80,8%, SAME) | 42.737 → 8.338 (-80,5%, FASTER) |
| boxBlur/i420-r2/1920x1080 | 532.941 → 99.855 (-81,3%, FASTER) | 349.249 → 70.048 (-79,9%, FASTER) |
| boxBlur/i420-r2/720x360 | 64.493 → 12.999 (-79,8%, FASTER) | 43.141 → 8.348 (-80,6%, FASTER) |
| crop/i420-inset-8/1920x1080 | 112.011 → 9.177 (-91,8%, FASTER) | 56.054 → 9.772 (-82,6%, SAME) |
| crop/i420-inset-8/720x360 | 12.925 → 0.854 (-93,4%, FASTER) | 5.795 → 0.311 (-94,6%, SAME) |
| flipHorizontal/i420-whole-frame/1920x1080 | 113.789 → 14.052 (-87,7%, FASTER) | 54.338 → 13.375 (-75,4%, FASTER) |
| flipHorizontal/i420-whole-frame/720x360 | 14.202 → 1.571 (-88,9%, FASTER) | 6.356 → 1.302 (-79,5%, FASTER) |
| flipVertical/i420-whole-frame/1920x1080 | 114.251 → 7.241 (-93,7%, FASTER) | 52.487 → 6.287 (-88,0%, SAME) |
| flipVertical/i420-whole-frame/720x360 | 14.039 → 0.877 (-93,8%, SAME) | 6.179 → 0.369 (-94,0%, FASTER) |
| rotate/i420-90/1920x1080 | 115.835 → 18.116 (-84,4%, SAME) | 57.065 → 27.045 (-52,6%, FASTER) |
| rotate/i420-90/720x360 | 13.849 → 2.039 (-85,3%, FASTER) | 6.304 → 2.643 (-58,1%, FASTER) |
| chromaSwap/nv12-whole-frame/1920x1080 | 87.015 → 8.823 (-89,9%, FASTER) | 44.411 → 6.983 (-84,3%, SAME) |
| chromaSwap/nv12-whole-frame/720x360 | 10.810 → 0.760 (-93,0%, SAME) | 4.977 → 0.293 (-94,1%, SAME) |

Fresh Windows raw verdicts and receipts are in `raw/`; the versioned tag baseline is `test/probe/baseline/windows-13th-gen-intel-r-core-tm-i9-13980hx-x64-release.json`.
