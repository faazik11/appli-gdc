import 'package:flutter/material.dart';

/// Pied de micro à perche, dessiné à la main (aucune police d'icônes n'en propose de lisible).
class StandIcon extends StatelessWidget {
  final double? size;
  final Color? color;

  const StandIcon({super.key, this.size, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final s = size ?? theme.size ?? 24;
    return SizedBox.square(
      dimension: s,
      child: CustomPaint(painter: _StandPainter(color ?? theme.color ?? Colors.black)),
    );
  }
}

class _StandPainter extends CustomPainter {
  final Color color;

  _StandPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    // Trépied
    const foot = Offset(10, 15.5);
    canvas.drawLine(foot, const Offset(3.5, 21.5), line);
    canvas.drawLine(foot, const Offset(16.5, 21.5), line);
    canvas.drawLine(foot, const Offset(10, 21.5), line);
    canvas.drawLine(const Offset(10, 8.5), foot, line);
    // Perche inclinée avec contrepoids, et le micro au bout
    canvas.drawLine(const Offset(5, 11), const Offset(19, 3.5), line);
    canvas.drawCircle(const Offset(5, 11), 1.6, fill);
    canvas.save();
    canvas.translate(20, 3);
    canvas.rotate(-0.5);
    canvas.drawRRect(RRect.fromLTRBR(-1, -2.4, 4, 2.4, const Radius.circular(2.4)), fill);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StandPainter old) => old.color != color;
}
