import 'package:flutter/painting.dart';

/// ZIVO v2 elevation — bright cards lifting off the warm ground on soft,
/// warm-tinted shadows. This is a primary source of the "alive" feel.
abstract final class AppShadows {
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x0A3C2D1E), // rgba(60,45,30,0.04)
      blurRadius: 4,
      offset: Offset(0, 2),
    ),
    BoxShadow(
      color: Color(0x243C2D1E), // rgba(60,45,30,0.14) softened by spread
      blurRadius: 30,
      spreadRadius: -16,
      offset: Offset(0, 14),
    ),
  ];

  static const List<BoxShadow> ember = [
    BoxShadow(
      color: Color(0x4DFF5A1F),
      blurRadius: 32,
      spreadRadius: -8,
      offset: Offset(0, 16),
    ),
  ];

  static const List<BoxShadow> pulse = [
    BoxShadow(
      color: Color(0x990A8F63),
      blurRadius: 18,
      spreadRadius: -8,
      offset: Offset(0, 8),
    ),
  ];
}
