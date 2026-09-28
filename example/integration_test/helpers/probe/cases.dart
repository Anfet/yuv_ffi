import 'cases/grayscale.dart';
import 'cases/black_white.dart';
import 'cases/negate.dart';
import 'cases/gaussian.dart';
import 'cases/box.dart';
import 'cases/mean.dart';
import 'cases/box_roi.dart';
import 'cases/mean_roi.dart';
import 'cases/crop.dart';
import 'cases/crop_even.dart';
import 'cases/cropped.dart';
import 'cases/flip_horizontal.dart';
import 'cases/flip_vertical.dart';
import 'cases/rotate_90.dart';
import 'cases/rotate_180.dart';
import 'cases/rotate_270.dart';
import 'cases/to_i420.dart';
import 'cases/to_nv12.dart';
import 'cases/to_bgra.dart';
import 'cases/to_bgra_bytes.dart';
import 'cases/rgba_in.dart';
import 'cases/chroma_swap.dart';

const probeCaseIds = <String>[
  ...grayscaleCases,
  ...blackwhiteCases,
  ...negateCases,
  ...gaussianCases,
  ...boxCases,
  ...meanCases,
  ...boxroiCases,
  ...meanroiCases,
  ...cropCases,
  ...cropevenCases,
  ...croppedCases,
  ...fliphorizontalCases,
  ...flipverticalCases,
  ...rotate90Cases,
  ...rotate180Cases,
  ...rotate270Cases,
  ...toi420Cases,
  ...tonv12Cases,
  ...tobgraCases,
  ...tobgrabytesCases,
  ...rgbainCases,
  ...chromaswapCases,
];
