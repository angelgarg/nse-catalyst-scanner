import 'package:flutter/widgets.dart';

/// Motion tokens (motion review 2026-10-29). Calm, symmetrical for up/down,
/// never looping on data, and zero when the user turns animations off.
abstract final class Motion {
  static const micro = Duration(milliseconds: 120);
  static const short = Duration(milliseconds: 200);
  static const medium = Duration(milliseconds: 320);
  static const long = Duration(milliseconds: 600);
  static const settle = Duration(milliseconds: 1200);

  static const curve = Curves.easeOutCubic;
  static const emphasized = Curves.easeInOutCubicEmphasized;

  static bool reduced(BuildContext c) =>
      MediaQuery.maybeDisableAnimationsOf(c) ?? false;

  static Duration of(BuildContext c, Duration d) =>
      reduced(c) ? Duration.zero : d;
}
