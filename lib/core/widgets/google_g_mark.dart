import 'package:flutter/material.dart';

/// The official four-colour Google "G", drawn directly from its vector paths
/// (no bundled image asset — mirroring [GoogleDriveMark] and how the rest of the
/// app renders brand marks). Use on the "Continue with Google" sign-in button so
/// it carries Google's actual logo rather than an approximated glyph.
class GoogleGMark extends StatelessWidget {
  const GoogleGMark({this.size = 20, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleGPainter()),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  // Google's brand colours for the mark.
  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  // The four official Google "G" segments, authored on a 48×48 viewBox.
  static const _bluePath =
      'M47.532 24.5528C47.532 22.9214 47.3997 21.2811 47.1175 19.6761H24.48V28.9181H37.4434C36.9055 31.8988 35.177 34.5356 32.6461 36.2111V42.2078H40.3801C44.9217 38.0278 47.532 31.8547 47.532 24.5528Z';
  static const _greenPath =
      'M24.48 48.0016C30.9529 48.0016 36.4116 45.8764 40.3888 42.2078L32.6549 36.2111C30.5031 37.6708 27.7252 38.5122 24.4888 38.5122C18.2275 38.5122 12.9187 34.2867 11.0139 28.6006H3.03296V34.7825C7.10718 42.8813 15.4056 48.0016 24.48 48.0016Z';
  static const _yellowPath =
      'M11.0051 28.6006C10.5017 27.1411 10.2018 25.5823 10.2018 23.9765C10.2018 22.3707 10.4863 20.8119 11.0051 19.3524V13.1707H3.03298C1.38352 16.4527 0.464355 20.1471 0.464355 23.9765C0.464355 27.8059 1.38352 31.5003 3.03298 34.7823L11.0051 28.6006Z';
  static const _redPath =
      'M24.48 9.44069C28.0324 9.44069 31.2172 10.6606 33.7204 13.0498L40.5602 6.20991C36.4319 2.36303 30.9645 0 24.48 0C15.4056 0 7.10718 5.12026 3.03296 13.2126L11.0051 19.3524C12.9187 13.6663 18.2275 9.44069 24.48 9.44069Z';

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48.0, size.height / 48.0);
    final paint = Paint()..isAntiAlias = true;
    canvas.drawPath(_parse(_bluePath), paint..color = _blue);
    canvas.drawPath(_parse(_greenPath), paint..color = _green);
    canvas.drawPath(_parse(_yellowPath), paint..color = _yellow);
    canvas.drawPath(_parse(_redPath), paint..color = _red);
    canvas.restore();
  }

  /// A tiny SVG-path reader supporting the commands these marks use: absolute
  /// M/L/H/V/C and Z (plus their relative lowercase variants). Enough to render
  /// the Google logo without pulling in a full SVG dependency.
  Path _parse(String data) {
    final path = Path();
    final tokens = _tokenize(data);
    var i = 0;
    double cx = 0, cy = 0; // current point
    double sx = 0, sy = 0; // subpath start (for Z)
    String cmd = '';

    double num() => tokens[i++] as double;

    while (i < tokens.length) {
      final t = tokens[i];
      if (t is String) {
        cmd = t;
        i++;
      }
      switch (cmd) {
        case 'M':
          cx = num();
          cy = num();
          path.moveTo(cx, cy);
          sx = cx;
          sy = cy;
          cmd = 'L'; // subsequent coords are implicit line-tos
        case 'm':
          cx += num();
          cy += num();
          path.moveTo(cx, cy);
          sx = cx;
          sy = cy;
          cmd = 'l';
        case 'L':
          cx = num();
          cy = num();
          path.lineTo(cx, cy);
        case 'l':
          cx += num();
          cy += num();
          path.lineTo(cx, cy);
        case 'H':
          cx = num();
          path.lineTo(cx, cy);
        case 'h':
          cx += num();
          path.lineTo(cx, cy);
        case 'V':
          cy = num();
          path.lineTo(cx, cy);
        case 'v':
          cy += num();
          path.lineTo(cx, cy);
        case 'C':
          final x1 = num(), y1 = num(), x2 = num(), y2 = num();
          cx = num();
          cy = num();
          path.cubicTo(x1, y1, x2, y2, cx, cy);
        case 'c':
          final x1 = cx + num(), y1 = cy + num(), x2 = cx + num(), y2 = cy + num();
          final ex = cx + num(), ey = cy + num();
          path.cubicTo(x1, y1, x2, y2, ex, ey);
          cx = ex;
          cy = ey;
        case 'Z':
        case 'z':
          path.close();
          cx = sx;
          cy = sy;
      }
    }
    return path;
  }

  /// Splits path data into command letters (as String) and numbers (as double).
  List<Object> _tokenize(String data) {
    final out = <Object>[];
    final number = RegExp(r'[-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?');
    var i = 0;
    while (i < data.length) {
      final ch = data[i];
      if (RegExp(r'[a-zA-Z]').hasMatch(ch)) {
        out.add(ch);
        i++;
      } else if (ch == ' ' || ch == ',' || ch == '\n' || ch == '\t' || ch == '\r') {
        i++;
      } else {
        final m = number.matchAsPrefix(data, i);
        if (m == null) {
          i++;
          continue;
        }
        out.add(double.parse(m.group(0)!));
        i = m.end;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
