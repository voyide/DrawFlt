import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'models.dart';

double _clamp01(double v) => v.clamp(0.0, 1.0);

/// Generates a procedural brush stamp as a [ui.Image].
Future<ui.Image> generateStampImage({
  required BrushShape shape,
  required Color color,
  required int seed,
  required int imageSize,
  required double softness,
  required double feather,
  required double grain,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, imageSize.toDouble(), imageSize.toDouble()),
  );
  final sz = imageSize.toDouble();
  final half = sz / 2;

  // Draw procedural shape centered at (half, half)
  _drawProceduralShape(canvas, half, half, half * 0.92, shape, color, seed);

  // Core ellipse
  final rng = SeededRng(seed + 999);
  final coreR = half * (0.02 + _clamp01(shape.core) * 0.22);
  final coreRx = coreR * rng.range(0.7, 1.2);
  final coreRy = coreR * rng.range(0.7, 1.2);
  final corePaint = Paint()
    ..color = color.withValues(alpha: rng.range(0.12, 0.6));
  canvas.save();
  canvas.translate(half, half);
  canvas.drawOval(
    Rect.fromCenter(center: Offset.zero, width: coreRx * 2, height: coreRy * 2),
    corePaint,
  );
  canvas.restore();

  final basePicture = recorder.endRecording();
  ui.Image baseImage = await basePicture.toImage(imageSize, imageSize);

  // Shadow
  if (shape.shadowOpacity > 0.001 && shape.shadowSize > 0.001) {
    baseImage = await _applyShadow(baseImage, imageSize, shape.shadowSize, shape.shadowOpacity);
  }

  // Softness (blur)
  if (softness > 0.001) {
    baseImage = await _applyBlur(baseImage, imageSize, softness);
  }

  // Feather
  if (feather > 0.001) {
    baseImage = await _applyFeather(baseImage, imageSize, feather);
  }

  // Grain
  if (grain > 0.001) {
    baseImage = await _applyGrain(baseImage, imageSize, grain);
  }

  return baseImage;
}

void _drawProceduralShape(Canvas canvas, double cx, double cy, double R,
    BrushShape shape, Color color, int seed) {
  final rng = SeededRng(seed);
  final folds = shape.symmetry.clamp(2, 5);
  final wedge = 2 * pi / folds;
  final margin = wedge * 0.08;
  final density = _clamp01(shape.density);
  final complexity = shape.complexity.clamp(1, 30);
  final organic = _clamp01(shape.organic);
  final roundK = _clamp01(shape.roundness);
  final baseCount = 3 + (complexity * 2.0).round() + (density * 12).round();

  final types = ['ellipse', 'rect', 'poly', 'ellipse', 'ellipse', 'rect'];

  // Generate base primitives
  final primitives = <_Primitive>[];
  for (int i = 0; i < baseCount; i++) {
    final primType = rng.choice(types);
    final a = rng.range(-wedge / 2 + margin, wedge / 2 - margin);
    final wobA = (rng.next() - 0.5) * wedge * 0.25 * organic;
    final wobR = (rng.next() - 0.5) * R * 0.25 * organic;
    final rad = (rng.range(R * 0.05, R) + wobR).clamp(R * 0.04, R);
    final radians = a + wobA;
    final px = rad * cos(radians);
    final py = rad * sin(radians);
    final opacity = (rng.next() * 0.85 + 0.1).clamp(0.12, 0.95);

    if (primType == 'ellipse') {
      final scaleMax = 0.22 + complexity * 0.02;
      final rx = rng.range(R * 0.03, R * scaleMax) *
          (1 + (rng.next() - 0.5) * 0.6 * organic);
      final ry = rng.range(R * 0.03, R * scaleMax) *
          (1 + (rng.next() - 0.5) * 0.6 * organic);
      final rot = rng.range(-90, 90) + (rng.next() - 0.5) * 50 * organic;
      primitives.add(_Primitive(
        type: 'ellipse',
        cx: px, cy: py,
        rx: rx, ry: ry,
        rot: rot * pi / 180,
        opacity: opacity,
      ));
    } else if (primType == 'rect') {
      final w = rng.range(R * 0.05, R * (0.22 + complexity * 0.04));
      final h = rng.range(R * 0.05, R * (0.22 + complexity * 0.04));
      final rot = rng.range(-90, 90) + (rng.next() - 0.5) * 50 * organic;
      final rr = min(w, h) * (0.05 + 0.45 * roundK);
      primitives.add(_Primitive(
        type: 'rect',
        cx: px, cy: py,
        w: w, h: h,
        rr: rr,
        rot: rot * pi / 180,
        opacity: opacity,
      ));
    } else {
      final n = rng.rangeInt(3, 6);
      final pts = <Offset>[];
      for (int j = 0; j < n; j++) {
        final aa = rng.range(-wedge / 2 + margin, wedge / 2 - margin) +
            (rng.next() - 0.5) * wedge * 0.3 * organic;
        final rr = rng.range(R * 0.07, R).clamp(R * 0.06, R);
        pts.add(Offset(rr * cos(aa), rr * sin(aa)));
      }
      final rot = rng.range(-30, 30);
      primitives.add(_Primitive(
        type: 'poly',
        cx: 0, cy: 0,
        rot: rot * pi / 180,
        opacity: opacity,
        polyPts: pts,
      ));
    }
  }

  // Draw with rotational symmetry
  for (int k = 0; k < folds; k++) {
    final foldAngle = k * wedge;
    for (final p in primitives) {
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(foldAngle);

      final paint = Paint()
        ..color = color.withValues(alpha: p.opacity)
        ..style = PaintingStyle.fill;

      if (p.type == 'ellipse') {
        canvas.save();
        canvas.translate(p.cx, p.cy);
        canvas.rotate(p.rot);
        canvas.drawOval(
          Rect.fromCenter(
              center: Offset.zero, width: p.rx * 2, height: p.ry * 2),
          paint,
        );
        canvas.restore();
      } else if (p.type == 'rect') {
        canvas.save();
        canvas.translate(p.cx, p.cy);
        canvas.rotate(p.rot);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: p.w, height: p.h),
            Radius.circular(p.rr),
          ),
          paint,
        );
        canvas.restore();
      } else if (p.type == 'poly' && p.polyPts != null && p.polyPts!.length >= 3) {
        canvas.save();
        canvas.rotate(p.rot);
        final path = Path();
        path.moveTo(p.polyPts![0].dx, p.polyPts![0].dy);
        for (int i = 1; i < p.polyPts!.length; i++) {
          path.lineTo(p.polyPts![i].dx, p.polyPts![i].dy);
        }
        path.close();
        canvas.drawPath(path, paint);
        canvas.restore();
      }

      canvas.restore();
    }
  }
}

Future<ui.Image> _applyShadow(
    ui.Image src, int size, double shadowSize, double shadowOpacity) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()));

  // Draw blurred shadow
  final sigma = shadowSize * size * 0.10;
  canvas.drawImage(
    src,
    Offset.zero,
    Paint()
      ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma)
      ..colorFilter = ColorFilter.mode(
          Colors.black.withValues(alpha: shadowOpacity), BlendMode.srcIn),
  );

  // Draw original on top
  canvas.drawImage(src, Offset.zero, Paint());

  final pic = recorder.endRecording();
  return pic.toImage(size, size);
}

Future<ui.Image> _applyBlur(ui.Image src, int size, double softness) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()));
  final maxBlur = size * 0.06;
  canvas.drawImage(
    src,
    Offset.zero,
    Paint()..imageFilter = ui.ImageFilter.blur(
        sigmaX: softness * maxBlur, sigmaY: softness * maxBlur),
  );
  final pic = recorder.endRecording();
  return pic.toImage(size, size);
}

Future<ui.Image> _applyFeather(ui.Image src, int size, double feather) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()));
  final sz = size.toDouble();
  final half = sz / 2;

  canvas.drawImage(src, Offset.zero, Paint());

  final r0 = (1 - feather) * half;
  final gradient = ui.Gradient.radial(
    Offset(half, half),
    half,
    [const Color(0xFFFFFFFF), const Color(0x00FFFFFF)],
    [r0 / half, 1.0],
  );
  canvas.drawRect(
    Rect.fromLTWH(0, 0, sz, sz),
    Paint()
      ..shader = gradient
      ..blendMode = BlendMode.dstIn,
  );

  final pic = recorder.endRecording();
  return pic.toImage(size, size);
}

Future<ui.Image> _applyGrain(ui.Image src, int size, double grain) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()));

  canvas.drawImage(src, Offset.zero, Paint());

  // Generate noise
  final noiseRec = ui.PictureRecorder();
  final noiseCanvas = Canvas(noiseRec, Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()));
  final rng = Random();
  final amp = (255 * grain * 0.6).round();
  final step = max(1, size ~/ 128);
  for (int y = 0; y < size; y += step) {
    for (int x = 0; x < size; x += step) {
      final a = (255 - rng.nextInt(amp + 1)).clamp(0, 255);
      noiseCanvas.drawRect(
        Rect.fromLTWH(x.toDouble(), y.toDouble(), step.toDouble(), step.toDouble()),
        Paint()..color = Color.fromARGB(a, 255, 255, 255),
      );
    }
  }
  final noisePic = noiseRec.endRecording();
  final noiseImg = await noisePic.toImage(size, size);

  canvas.drawImage(noiseImg, Offset.zero, Paint()..blendMode = BlendMode.dstIn);
  noiseImg.dispose();

  final pic = recorder.endRecording();
  return pic.toImage(size, size);
}

class _Primitive {
  final String type;
  final double cx, cy;
  final double rx, ry;
  final double w, h, rr;
  final double rot;
  final double opacity;
  final List<Offset>? polyPts;

  _Primitive({
    required this.type,
    this.cx = 0,
    this.cy = 0,
    this.rx = 0,
    this.ry = 0,
    this.w = 0,
    this.h = 0,
    this.rr = 0,
    this.rot = 0,
    this.opacity = 1.0,
    this.polyPts,
  });
}
