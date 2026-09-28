# Box blur visual comparison: RGB vs Y-only

- Source: `test/assets/test_pattern_512.png`, converted to I420 and decoded once for the shared input.
- Filter: box blur, radius 10, clamp-to-edge border.
- Left panel: shared decoded input.
- Center panel: blur R/G/B, then encode/decode I420 for display.
- Right panel: blur only the Y plane with an integer separable sum; copy U/V unchanged, then decode I420 for display.
- This is a visual comparison, not a native benchmark or a production ABI output test. The synthetic pattern deliberately includes high-contrast color bars, gradients, and a fine checkerboard to expose chroma differences. It does not establish how visible the difference is on ordinary camera footage.
