# BLUR-02: isolated direct-YUV Mean candidate

The Mean candidates were built and run independently from
`yuv_mean_blur_v1.c` in detached worktrees from `2285ca9`; production C and
ABI were untouched. A source diff confirms Mean and Box differ only by names
and exports, then each Mean candidate was compiled into its own Android
Release/AOT library and reached `yuv_mean_blur_v1` through public
`applyMeanBlur`.

| Input | Variant | Raw ms | Median | Spread | Saved vs RGB | Saving |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 1477x1065 | RGB baseline | 54.504, 52.894, 54.561, 53.109, 54.374, 52.832, 54.375 | 54.374 | 1.729 | — | — |
| 1477x1065 | Y-only | 12.771, 11.258, 12.797, 11.155, 12.695, 11.183, 12.875 | 12.695 | 1.720 | 41.679 ms | 76.65% |
| 1477x1065 | Y/U/V | 18.045, 16.444, 18.158, 16.449, 18.053, 16.460, 18.005 | 18.005 | 1.714 | 36.369 ms | 66.89% |
| 720x360 | RGB baseline | 8.683, 9.136, 8.635, 8.637, 9.042, 8.626, 8.644 | 8.644 | 0.510 | — | — |
| 720x360 | Y-only | 1.648, 2.226, 1.638, 1.631, 2.038, 1.700, 1.633 | 1.648 | 0.595 | 6.996 ms | 80.94% |
| 720x360 | Y/U/V | 2.532, 3.114, 2.537, 2.538, 2.946, 2.537, 2.572 | 2.538 | 0.582 | 6.106 ms | 70.64% |

All calls returned success and each candidate produced a stable checksum over
two warmups plus seven samples. The direct Mean output checksums match the
already accepted direct Box candidates byte-for-byte: Y-only
`6f06f4c2…3214b12f` / `9c86fad…aed20b78`, Y/U/V
`4bddeb4b…d376d77a` / `27f492f…c93831fa`. Therefore the three BLUR-01
decoded PNGs are reused after that byte comparison: `blur01_box_rgb.png`,
`blur01_box_yonly.png`, and `blur01_box_yuv.png`. They represent the same
direct output bytes; RGB uses RGB blur and re-encode, Y-only retains source
UV, and Y/U/V blurs chroma at radius 5.

## Addressed timing control

The initial Y/U/V run was unexpectedly slow and noisy: 40.750 ms / 6.629 ms
with spreads of 7.099 ms / 2.335 ms. It remains preserved as the original raw
record in `blur02_raw/yuv/`, but is not representative and is not used for the
comparison above. After a short idle interval, a fresh Android Release/AOT
Mean-only run on the same Pixel 3 produced the table's 18.005 ms / 2.538 ms
medians. Its output checksums are unchanged. The complete control JSONL and
device log are in `blur02_control/mean_then_box/mean/`.

The control matches the previously measured direct Y/U/V Box medians (17.967
ms / 2.548 ms) closely: the differences are +0.038 ms and -0.010 ms. The
candidate C sources have identical executable algorithm bodies after
substituting `box`/`Box`/`BOX` identifiers with `mean`/`Mean`/`MEAN`; the only
remaining textual distinction is the deliberate comment that says the two
normalized kernels share an oracle. Both public calls use the common ABI
runner, with `applyBoxBlur` dispatching to `yuv_box_blur_v1` and
`applyMeanBlur` to `yuv_mean_blur_v1`. The first Mean Y/U/V session is
consistent with inter-session runtime variability rather than a distinct
kernel or dispatch path; the exact cause is unknown. It demonstrates that the 66.89% / 70.64%
control-session savings are informative but not a durable performance promise;
the first session must accompany every review and no production threshold is
accepted from this experiment. One attempted paired Box wrapper failed before
measurement because its child PowerShell host did not expose `Get-FileHash`;
the host error is retained next to the successful control. After Mean's control
aligned with the previous Box result, a paired Box re-run was not needed.

Timing covers the full public Dart call and native transport, but excludes PNG
decode, deterministic packed-UV creation, and source clone. Raw JSONL/logcat:
`blur02_raw/yonly/`, `blur02_raw/yuv/`, and `blur02_control/`.
