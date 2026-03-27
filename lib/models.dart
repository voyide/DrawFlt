import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

// ───────────── Seeded RNG (matches JS: LCG) ─────────────
class SeededRng {
  int _state;
  SeededRng(int seed) : _state = seed & 0xFFFFFFFF;

  double next() {
    _state = ((_state * 1664525) + 1013904223) & 0xFFFFFFFF;
    return (_state & 0xFFFFFFFF) / 0x100000000;
  }

  double range(double a, double b) => a + (b - a) * next();
  int rangeInt(int a, int b) => a + (next() * (b - a + 1)).floor().clamp(0, b - a);
  T choice<T>(List<T> arr) => arr[(next() * arr.length).floor().clamp(0, arr.length - 1)];
}

// ───────────── Brush Shape Parameters ─────────────
class BrushShape {
  int symmetry;
  int complexity;
  double density;
  double organic;
  double core;
  double roundness;
  double shadowSize;
  double shadowOpacity;

  BrushShape({
    this.symmetry = 3,
    this.complexity = 11,
    this.density = 0.53,
    this.organic = 0.43,
    this.core = 0.23,
    this.roundness = 0.40,
    this.shadowSize = 0.20,
    this.shadowOpacity = 0.35,
  });

  BrushShape copy() => BrushShape(
        symmetry: symmetry,
        complexity: complexity,
        density: density,
        organic: organic,
        core: core,
        roundness: roundness,
        shadowSize: shadowSize,
        shadowOpacity: shadowOpacity,
      );
}

// ───────────── Jitter ─────────────
class JitterSettings {
  double size;
  double angle; // degrees
  double opacity;
  double spacing;

  JitterSettings({
    this.size = 0.05,
    this.angle = 10,
    this.opacity = 0.10,
    this.spacing = 0.0,
  });

  JitterSettings copy() => JitterSettings(
        size: size,
        angle: angle,
        opacity: opacity,
        spacing: spacing,
      );
}

// ───────────── Full Brush Settings ─────────────
class BrushSettings {
  Color color;
  int seed;
  BrushShape shape;

  double softness;
  double feather;
  double grain;

  double size;
  double spacing;
  double flow;
  double smoothing;
  double angleSmoothing;
  double scatter;
  bool followAngle;
  BlendMode blendMode;
  double angleOffsetDeg;

  JitterSettings jitter;

  ui.Image? stampImage;
  bool ready;

  BrushSettings({
    this.color = const Color(0xFF1A1A1A),
    int? seed,
    BrushShape? shape,
    this.softness = 0.0,
    this.feather = 0.0,
    this.grain = 0.0,
    this.size = 512,
    this.spacing = 0.15,
    this.flow = 1.0,
    this.smoothing = 0.15,
    this.angleSmoothing = 0.0,
    this.scatter = 0.0,
    this.followAngle = true,
    this.blendMode = BlendMode.srcOver,
    this.angleOffsetDeg = 0,
    JitterSettings? jitter,
    this.stampImage,
    this.ready = false,
  })  : seed = seed ?? Random().nextInt(0xFFFFFFFF),
        shape = shape ?? BrushShape(),
        jitter = jitter ?? JitterSettings();
}

// ───────────── Stamp Point ─────────────
class StampPoint {
  final double x, y, size, angle, alpha;
  const StampPoint(
      {required this.x,
      required this.y,
      required this.size,
      required this.angle,
      required this.alpha});
}

// ───────────── Stroke Data ─────────────
class StrokeData {
  final ui.Image stampImage;
  final BlendMode blendMode;
  final List<StampPoint> stamps;
  final int layerId;

  StrokeData({
    required this.stampImage,
    required this.blendMode,
    required this.stamps,
    required this.layerId,
  });
}

// ───────────── Layer ─────────────
class DrawingLayer {
  final int id;
  String name;
  bool visible;
  double opacity;
  BlendMode blendMode;
  String maskMode; // 'none', 'alpha', 'alpha-invert'
  double glowSize;
  double glowStrength;

  List<StrokeData> strokes;
  ui.Image? cachedImage;

  DrawingLayer({
    required this.id,
    required this.name,
    this.visible = true,
    this.opacity = 1.0,
    this.blendMode = BlendMode.srcOver,
    this.maskMode = 'none',
    this.glowSize = 30,
    this.glowStrength = 50,
    List<StrokeData>? strokes,
    this.cachedImage,
  }) : strokes = strokes ?? [];
}

// ───────────── Undo Action ─────────────
abstract class UndoAction {}

class StrokeUndoAction extends UndoAction {
  final int layerId;
  final StrokeData stroke;
  StrokeUndoAction({required this.layerId, required this.stroke});
}

class ClearUndoAction extends UndoAction {
  final List<LayerSnapshot> snapshots;
  ClearUndoAction({required this.snapshots});
}

class LayerSnapshot {
  final int id;
  final String name;
  final bool visible;
  final double opacity;
  final BlendMode blendMode;
  final String maskMode;
  final double glowSize;
  final double glowStrength;
  final List<StrokeData> strokes;

  LayerSnapshot({
    required this.id,
    required this.name,
    required this.visible,
    required this.opacity,
    required this.blendMode,
    required this.maskMode,
    required this.glowSize,
    required this.glowStrength,
    required this.strokes,
  });
}

// ───────────── HSV Color Pick State ─────────────
class ColorPick {
  double h; // 0..360
  double s; // 0..1
  double v; // 0..1
  double a; // 0..1

  ColorPick({this.h = 0, this.s = 0, this.v = 0.1, this.a = 1.0});

  Color toColor() {
    return HSVColor.fromAHSV(a, h.clamp(0, 360), s.clamp(0, 1), v.clamp(0, 1)).toColor();
  }

  void setFromColor(Color c) {
    final hsv = HSVColor.fromColor(c);
    h = hsv.hue;
    s = hsv.saturation;
    v = hsv.value;
    a = c.alpha / 255.0;
  }

  String toHex() {
    final c = toColor();
    return '#${c.red.toRadixString(16).padLeft(2, '0')}'
        '${c.green.toRadixString(16).padLeft(2, '0')}'
        '${c.blue.toRadixString(16).padLeft(2, '0')}'
        '${c.alpha.toRadixString(16).padLeft(2, '0')}'
            .toUpperCase();
  }

  String toRgbaString() {
    final c = toColor();
    return 'rgba(${c.red}, ${c.green}, ${c.blue}, ${a.toStringAsFixed(2)})';
  }
}
