import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'models.dart';

class ColorWheelPicker extends StatefulWidget {
  final ColorPick pick;
  final VoidCallback onChanged;

  const ColorWheelPicker(
      {super.key, required this.pick, required this.onChanged});

  @override
  State<ColorWheelPicker> createState() => _ColorWheelPickerState();
}

class _ColorWheelPickerState extends State<ColorWheelPicker> {
  bool _draggingHue = false;
  bool _draggingSV = false;

  static const double ringThickness = 28;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Wheel + SV square ──
        LayoutBuilder(builder: (ctx, constraints) {
          final size = min(constraints.maxWidth, 400.0);
          final innerRadius = size / 2 - ringThickness - 6;
          final svSide = (innerRadius * sqrt2 * 0.96).clamp(44.0, size);

          return SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Hue ring
                GestureDetector(
                  onPanStart: (d) {
                    _draggingHue = true;
                    _updateHue(d.localPosition, size);
                  },
                  onPanUpdate: (d) {
                    if (_draggingHue) _updateHue(d.localPosition, size);
                  },
                  onPanEnd: (_) => _draggingHue = false,
                  child: CustomPaint(
                    size: Size(size, size),
                    painter: _HueRingPainter(ringThickness),
                  ),
                ),

                // Hue cursor
                _buildHueCursor(size),

                // SV square
                GestureDetector(
                  onPanStart: (d) {
                    _draggingSV = true;
                    _updateSV(d.localPosition, svSide);
                  },
                  onPanUpdate: (d) {
                    if (_draggingSV) _updateSV(d.localPosition, svSide);
                  },
                  onPanEnd: (_) => _draggingSV = false,
                  child: Container(
                    width: svSide,
                    height: svSide,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.20),
                            blurRadius: 30,
                            offset: const Offset(0, 10)),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: CustomPaint(
                        size: Size(svSide, svSide),
                        painter: _SVSquarePainter(widget.pick.h),
                      ),
                    ),
                  ),
                ),

                // SV cursor
                _buildSVCursor(svSide),
              ],
            ),
          );
        }),

        const SizedBox(height: 16),

        // ── Alpha slider ──
        Row(
          children: [
            const Text('Alpha', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 12),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 10,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                ),
                child: Slider(
                  value: widget.pick.a,
                  onChanged: (v) {
                    widget.pick.a = v;
                    widget.onChanged();
                    setState(() {});
                  },
                ),
              ),
            ),
            Text('${(widget.pick.a * 100).round()}%',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),

        const SizedBox(height: 8),

        // ── Color codes ──
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: widget.pick.toColor(),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.black12),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _chip(widget.pick.toHex()),
                  _chip(widget.pick.toRgbaString()),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black12),
      ),
      child: Text(text,
          style: const TextStyle(
              fontSize: 11, fontFamily: 'monospace', color: Colors.black87)),
    );
  }

  void _updateHue(Offset local, double size) {
    final cx = size / 2, cy = size / 2;
    final angle = atan2(local.dy - cy, local.dx - cx);
    widget.pick.h = (angle * 180 / pi + 360) % 360;
    widget.onChanged();
    setState(() {});
  }

  void _updateSV(Offset local, double side) {
    widget.pick.s = (local.dx / side).clamp(0, 1);
    widget.pick.v = (1 - local.dy / side).clamp(0, 1);
    widget.onChanged();
    setState(() {});
  }

  Widget _buildHueCursor(double size) {
    final r = size / 2 - ringThickness / 2 - 1;
    final th = widget.pick.h * pi / 180;
    final x = size / 2 + r * cos(th) - 9;
    final y = size / 2 + r * sin(th) - 9;
    return Positioned(
      left: x,
      top: y,
      child: IgnorePointer(
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4), blurRadius: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSVCursor(double svSide) {
    final parentCenter = Offset.zero; // relative to center of parent
    final cursorX = widget.pick.s * svSide - svSide / 2 - 7;
    final cursorY = (1 - widget.pick.v) * svSide - svSide / 2 - 7;
    return Positioned(
      left: null,
      top: null,
      child: Transform.translate(
        offset: Offset(cursorX, cursorY),
        child: IgnorePointer(
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4), blurRadius: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HueRingPainter extends CustomPainter {
  final double thickness;
  _HueRingPainter(this.thickness);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final r = size.width / 2 - thickness / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness;

    for (int deg = 0; deg < 360; deg++) {
      final a0 = (deg - 0.5) * pi / 180;
      final a1 = (deg + 1.5) * pi / 180;
      paint.color = HSVColor.fromAHSV(1, deg.toDouble(), 1, 1).toColor();
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        a0,
        a1 - a0,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SVSquarePainter extends CustomPainter {
  final double hue;
  _SVSquarePainter(this.hue);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Base hue fill
    canvas.drawRect(
        rect, Paint()..color = HSVColor.fromAHSV(1, hue, 1, 1).toColor());

    // White gradient (left to right)
    final whiteGrad = ui.Gradient.linear(
      Offset.zero,
      Offset(size.width, 0),
      [Colors.white, Colors.white.withValues(alpha: 0)],
    );
    canvas.drawRect(rect, Paint()..shader = whiteGrad);

    // Black gradient (top to bottom)
    final blackGrad = ui.Gradient.linear(
      Offset.zero,
      Offset(0, size.height),
      [Colors.black.withValues(alpha: 0), Colors.black],
    );
    canvas.drawRect(rect, Paint()..shader = blackGrad);
  }

  @override
  bool shouldRepaint(covariant _SVSquarePainter old) => old.hue != hue;
}
