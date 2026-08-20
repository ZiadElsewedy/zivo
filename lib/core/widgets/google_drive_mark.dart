import 'package:flutter/material.dart';

/// The Google Drive tri-colour triangle mark, drawn directly (no bundled image
/// asset — mirroring how the sign-in screen draws its Google "G"). Sized to sit
/// inside a settings-row leading chip.
class GoogleDriveMark extends StatelessWidget {
  const GoogleDriveMark({this.size = 18, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _DriveMarkPainter()),
    );
  }
}

class _DriveMarkPainter extends CustomPainter {
  static const Color _blue = Color(0xFF2684FC);
  static const Color _green = Color(0xFF00AC47);
  static const Color _yellow = Color(0xFFFFD04B);

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    Offset p(double x, double y) => Offset(x * w, y * h);

    // A triangular ring of three colour bars — Google Drive's mark: yellow
    // along the bottom, blue up the left edge, green up the right edge, with a
    // triangular gap in the middle.
    final Offset a = p(0.50, 0.10); // outer apex
    final Offset b = p(0.08, 0.86); // outer bottom-left
    final Offset c = p(0.92, 0.86); // outer bottom-right
    final Offset ai = p(0.50, 0.40); // inner apex
    final Offset bi = p(0.31, 0.72); // inner bottom-left
    final Offset ci = p(0.69, 0.72); // inner bottom-right

    void fill(List<Offset> points, Color color) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = color);
    }

    fill([b, c, ci, bi], _yellow); // bottom bar
    fill([b, a, ai, bi], _blue); // left bar
    fill([a, c, ci, ai], _green); // right bar
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
