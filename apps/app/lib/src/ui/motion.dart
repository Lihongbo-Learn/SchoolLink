import 'package:flutter/animation.dart';

class AppMotion {
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration standard = Duration(milliseconds: 260);
  static const Duration page = Duration(milliseconds: 440);

  static const Curve enter = Curves.easeOutCubic;
  static const Curve emphasized = Cubic(0.16, 1, 0.3, 1);
  static const Curve exit = Curves.easeInCubic;
}
