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
  static const Color _yellow = Color(0xFFFFCF48);

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    Offset p(double x, double y) => Offset(x * w, y * h);

    // A triangle (apex up) split into three faces — the Drive colour cue.
    final Offset apex = p(0.50, 0.06);
    final Offset bottomLeft = p(0.06, 0.86);
    final Offset bottomRight = p(0.94, 0.86);
    final Offset midLeft = p(0.28, 0.46);
    final Offset midRight = p(0.72, 0.46);
    final Offset bottomMid = p(0.50, 0.86);
    final Offset centre = p(0.50, 0.59);

    void fill(List<Offset> points, Color color) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = color);
    }

    fill([apex, midLeft, centre, midRight], _yellow); // top face
    fill([midLeft, bottomLeft, bottomMid, centre], _blue); // lower-left face
    fill([midRight, bottomRight, bottomMid, centre], _green); // lower-right face
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
