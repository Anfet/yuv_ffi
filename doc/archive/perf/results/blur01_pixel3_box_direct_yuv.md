# BLUR-01: isolated direct-YUV Box candidate

Pixel 3 `8B1X11QLW`, Android 12, Release/AOT. The baseline is BLUR-00's
public `applyBoxBlur` on packed `Y + UV`; both candidates call that same public
Dart method and differ only in a temporary `yuv_box_blur_v1.c` inside an
uncommitted detached worktree. Production sources and ABI were not changed.

Each call used the same deterministic PNG-derived packed input, two warmups,
seven samples, radius Y=10, and source clone outside the timer. The candidates
accept only full-frame tight NV12/UV descriptors. Y-only copies UV; Y/U/V
blurs U and V independently at radius 5. This changes visible semantics from
the RGB baseline, whose filter runs in RGB then re-encodes 4:2:0 chroma.

| Input | Variant | Raw ms | Median | Spread | Saved vs RGB | Saving |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 1477x1065 | RGB baseline | 55.013, 53.481, 54.943, 53.601, 55.008, 53.397, 55.093 | 54.943 | 1.696 | — | — |
| 1477x1065 | Y-only | 12.738, 11.247, 12.806, 11.237, 12.846, 11.121, 12.789 | 12.738 | 1.725 | 42.205 ms | 76.82% |
| 1477x1065 | Y/U/V | 17.967, 16.426, 18.129, 16.601, 18.061, 16.493, 18.032 | 17.967 | 1.703 | 36.976 ms | 67.30% |
| 720x360 | RGB baseline | 8.535, 9.067, 8.540, 8.518, 9.047, 8.562, 8.564 | 8.562 | 0.549 | — | — |
| 720x360 | Y-only | 1.668, 2.234, 1.676, 1.640, 2.008, 1.690, 1.631 | 1.676 | 0.603 | 6.886 ms | 80.42% |
| 720x360 | Y/U/V | 2.518, 3.072, 2.557, 2.494, 3.010, 2.548, 2.542 | 2.548 | 0.578 | 6.014 ms | 70.24% |

Input SHA-256 is stable across all variants: `09ab1306d279f6b79bcc77dced485bc2d0691cf823aad82c0b5b1ad6f041cc78`
for 1477x1065 and `1fada775114bc0f90a9fb1338acdfd302c281331598400c328fde897106a289e`
for 720x360. Candidate result checksums differ from RGB as expected from the
semantic change: Y-only `6f06f4c2…3214b12f` / `9c86fad…aed20b78`; Y/U/V
`4bddeb4b…d376d77a` / `27f492f…c93831fa`.

Machine-readable timings and complete logcat are in `blur01_raw/yonly/` and
`blur01_raw/yuv/`. The candidate returns success for every recorded call and
checks identical output checksum across its nine repeated calls per input.

Visual PNGs were exported by a separate temporary Release/AOT app through its
own `getExternalFilesDir(null)` and pulled with `adb pull`; this app was not
used for the timing rows. Each is a 1477x1065 BGRA decode of the actual output:
`blur01_box_rgb.png` SHA-256 `f03be2ae5f4cd2a37da86cb13636441ab4b5bb8bf474bed368431465673787c5`,
`blur01_box_yonly.png` `682331ff7daff891ac3542705e8139de958751e398c21bd7dca2613286227699`,
and `blur01_box_yuv.png` `75a4cf4c54c43dadde6f3aeb88a2bee1ac773983e8934d46dc2e50b96a98fce9`.
Visual review: RGB and direct Y/U/V were judged indistinguishable on this
fixture; Y-only is visibly different because it retains the unblurred chroma.

The timing includes the public Dart transport and native result copy, exactly
as BLUR-00 does. It excludes PNG decode, conversion into the package input,
and source cloning. It therefore measures the intended end-to-end public call,
not only the native kernel.
