import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'models.dart';
import 'brush_generator.dart';

int _nearestPow2(int n) {
  int p = 1;
  while (p < n) {
    p <<= 1;
  }
  return p;
}

double _lerpAngle(double a, double b, double t) {
  final diff = atan2(sin(b - a), cos(b - a));
  return a + diff * t;
}

class DrawingState extends ChangeNotifier {
  // ───── World ─────
  final int worldWidth = 1800;
  final int worldHeight = 1800;
  Color backgroundColor = Colors.white;

  // ───── Brush ─────
  BrushSettings brush = BrushSettings();
  ColorPick colorPick = ColorPick(h: 0, s: 0, v: 0.1, a: 1.0);

  // ───── Layers ─────
  int _nextLayerId = 1;
  List<DrawingLayer> layers = [];
  int activeLayerIndex = 0;

  DrawingLayer? get activeLayer =>
      layers.isNotEmpty ? layers[activeLayerIndex.clamp(0, layers.length - 1)] : null;

  // ───── Camera ─────
  Matrix4 worldToScreen = Matrix4.identity();
  Matrix4 screenToWorld = Matrix4.identity();
  bool cameraInitialized = false;

  // ───── Drawing state ─────
  bool drawing = false;
  Offset? lastPoint;
  Offset? lastRaw;
  double carry = 0;
  double smoothedDirAngle = 0;
  StrokeData? activeStroke;

  // ───── Undo / Redo ─────
  final List<UndoAction> undoStack = [];
  final List<UndoAction> redoStack = [];
  static const int maxUndo = 30;

  // ───── Composited image ─────
  ui.Image? compositedWorld;

  DrawingState() {
    _addInitialLayer();
    _rebuildBrush();
  }

  void _addInitialLayer() {
    layers.add(DrawingLayer(id: _nextLayerId++, name: 'Layer 1'));
    activeLayerIndex = 0;
  }

  // ───── Brush building ─────
  bool _brushBuilding = false;

  Future<void> _rebuildBrush() async {
    if (_brushBuilding) return;
    _brushBuilding = true;

    final baseSize = _nearestPow2(brush.size.round()).clamp(64, 1024);
    try {
      final img = await generateStampImage(
        shape: brush.shape,
        color: brush.color,
        seed: brush.seed,
        imageSize: baseSize,
        softness: brush.softness,
        feather: brush.feather,
        grain: brush.grain,
      );
      brush.stampImage = img;
      brush.ready = true;
    } catch (_) {
      brush.ready = false;
    }
    _brushBuilding = false;
    notifyListeners();
  }

  void updateBrush() {
    brush.color = colorPick.toColor();
    _rebuildBrush();
  }

  void randomizeSeed() {
    brush.seed = Random().nextInt(0xFFFFFFFF);
    updateBrush();
  }

  void setColor(Color c) {
    colorPick.setFromColor(c);
    brush.color = colorPick.toColor();
    updateBrush();
  }

  void updateColorFromPick() {
    brush.color = colorPick.toColor();
    updateBrush();
  }

  // ───── Camera ─────
  void initCamera(Size viewSize) {
    final sx = viewSize.width / worldWidth;
    final sy = viewSize.height / worldHeight;
    final scale = min(sx, sy);
    final cx = viewSize.width / 2;
    final cy = viewSize.height / 2;
    final wcx = worldWidth / 2.0;
    final wcy = worldHeight / 2.0;

    worldToScreen = Matrix4.identity()
      ..translate(cx, cy)
      ..scale(scale, scale)
      ..translate(-wcx, -wcy);
    screenToWorld = Matrix4.copy(worldToScreen)..invert();
    cameraInitialized = true;
    notifyListeners();
  }

  Offset toWorld(Offset screen) {
  final v = screenToWorld.transform4(Vector4(screen.dx, screen.dy, 0, 1));
  return Offset(v.x / v.w, v.y / v.w);
  }

  void applyPanZoom(Matrix4 delta) {
    worldToScreen = delta * worldToScreen;
    screenToWorld = Matrix4.copy(worldToScreen)..invert();
    notifyListeners();
  }

  void resetCamera(Size viewSize) {
    initCamera(viewSize);
  }

  // ───── Drawing ─────
  double _getSpacing() {
    return max(1.0, brush.size * brush.spacing);
  }

  _StampParams _computeStampParams() {
    final j = brush.jitter;
    final rng = Random();
    double signed() => rng.nextDouble() * 2 - 1;

    final sizeJitter = 1 + signed() * j.size;
    final sz = max(1.0, brush.size * sizeJitter);

    final angleOffset = brush.angleOffsetDeg * pi / 180;
    final baseAngle = brush.followAngle ? smoothedDirAngle : 0.0;
    final angle = baseAngle + angleOffset + (signed() * j.angle) * pi / 180;

    final alpha = (brush.flow * (1 + signed() * j.opacity)).clamp(0.0, 1.0);

    final scatterR = brush.scatter * brush.size * rng.nextDouble();
    final scatterA = rng.nextDouble() * pi * 2;
    final offX = scatterR * cos(scatterA);
    final offY = scatterR * sin(scatterA);

    final spacing = max(1.0, _getSpacing() * (1 + signed() * j.spacing));

    return _StampParams(
        size: sz,
        angle: angle,
        alpha: alpha,
        offX: offX,
        offY: offY,
        spacing: spacing);
  }

  void beginStroke(Offset worldPoint) {
    final layer = activeLayer;
    if (layer == null || !brush.ready || brush.stampImage == null) return;

    drawing = true;
    carry = 0;
    smoothedDirAngle = 0;
    lastPoint = worldPoint;
    lastRaw = worldPoint;

    final params = _computeStampParams();
    activeStroke = StrokeData(
      stampImage: brush.stampImage!,
      blendMode: brush.blendMode,
      stamps: [],
      layerId: layer.id,
    );
    activeStroke!.stamps.add(StampPoint(
      x: worldPoint.dx + params.offX,
      y: worldPoint.dy + params.offY,
      size: params.size,
      angle: params.angle,
      alpha: params.alpha,
    ));
    notifyListeners();
  }

  void extendStroke(Offset currentWorld) {
    final layer = activeLayer;
    if (layer == null || activeStroke == null || lastRaw == null) return;

    // Smoothing
    final s = brush.smoothing.clamp(0.0, 0.9);
    final mix = s == 0 ? 1.0 : (1.0 - s);
    final smoothed = Offset(
      lastPoint!.dx + (currentWorld.dx - lastPoint!.dx) * mix,
      lastPoint!.dy + (currentWorld.dy - lastPoint!.dy) * mix,
    );
    lastPoint = smoothed;

    final from = lastRaw!;
    final dx = smoothed.dx - from.dx;
    final dy = smoothed.dy - from.dy;
    final dist = sqrt(dx * dx + dy * dy);
    if (dist < 0.1) return;

    final ang = atan2(dy, dx);
    final angS = brush.angleSmoothing.clamp(0.0, 0.9);
    smoothedDirAngle = _lerpAngle(smoothedDirAngle, ang, 1.0 - angS);

    double remaining = dist;
    double t = 0;
    while (true) {
      final params = _computeStampParams();
      final spacing = params.spacing;
      if (carry + remaining < spacing) break;

      final step = spacing - carry;
      t += step / dist;
      if (t > 1.0) break;
      final cx = from.dx + dx * t;
      final cy = from.dy + dy * t;

      activeStroke!.stamps.add(StampPoint(
        x: cx + params.offX,
        y: cy + params.offY,
        size: params.size,
        angle: params.angle,
        alpha: params.alpha,
      ));

      remaining -= step;
      carry = 0;
    }
    carry += remaining;
    lastRaw = smoothed;
    notifyListeners();
  }

  void endStroke() {
    if (activeStroke != null && activeStroke!.stamps.isNotEmpty) {
      final layer = layers.firstWhere(
        (l) => l.id == activeStroke!.layerId,
        orElse: () => layers.first,
      );
      layer.strokes.add(activeStroke!);
      _updateLayerCache(layer);

      undoStack.add(StrokeUndoAction(
        layerId: layer.id,
        stroke: activeStroke!,
      ));
      if (undoStack.length > maxUndo) undoStack.removeAt(0);
      redoStack.clear();
    }
    activeStroke = null;
    drawing = false;
    carry = 0;
    _recompose();
    notifyListeners();
  }

  Future<void> _updateLayerCache(DrawingLayer layer) async {
    final sz = Size(worldWidth.toDouble(), worldHeight.toDouble());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & sz);

    // Draw all strokes for this layer
    for (final stroke in layer.strokes) {
      _paintStroke(canvas, stroke);
    }

    final pic = recorder.endRecording();
    layer.cachedImage?.dispose();
    layer.cachedImage = await pic.toImage(worldWidth, worldHeight);
    notifyListeners();
  }

  void _paintStroke(Canvas canvas, StrokeData stroke) {
    for (final st in stroke.stamps) {
      canvas.save();
      canvas.translate(st.x, st.y);
      canvas.rotate(st.angle);
      final half = st.size / 2;
      canvas.drawImageRect(
        stroke.stampImage,
        Rect.fromLTWH(0, 0, stroke.stampImage.width.toDouble(),
            stroke.stampImage.height.toDouble()),
        Rect.fromLTWH(-half, -half, st.size, st.size),
        Paint()
          ..color = Color.fromARGB((st.alpha * 255).round(), 255, 255, 255)
          ..blendMode = stroke.blendMode
          ..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
    }
  }

  // ───── Undo / Redo ─────
  void undo() {
    if (drawing) endStroke();
    if (undoStack.isEmpty) return;
    final action = undoStack.removeLast();
    redoStack.add(action);

    if (action is StrokeUndoAction) {
      final layer = layers.firstWhere(
        (l) => l.id == action.layerId,
        orElse: () => layers.first,
      );
      if (layer.strokes.isNotEmpty) {
        layer.strokes.removeLast();
        _updateLayerCache(layer);
      }
    } else if (action is ClearUndoAction) {
      _restoreSnapshots(action.snapshots);
    }
    _recompose();
    notifyListeners();
  }

  void redo() {
    if (drawing) endStroke();
    if (redoStack.isEmpty) return;
    final action = redoStack.removeLast();
    undoStack.add(action);

    if (action is StrokeUndoAction) {
      final layer = layers.firstWhere(
        (l) => l.id == action.layerId,
        orElse: () => layers.first,
      );
      layer.strokes.add(action.stroke);
      _updateLayerCache(layer);
    } else if (action is ClearUndoAction) {
      _clearAllInternal();
    }
    _recompose();
    notifyListeners();
  }

  void clearAll() {
    if (drawing) endStroke();
    final snapshots = _takeSnapshots();
    _clearAllInternal();
    undoStack.add(ClearUndoAction(snapshots: snapshots));
    if (undoStack.length > maxUndo) undoStack.removeAt(0);
    redoStack.clear();
    _recompose();
    notifyListeners();
  }

  void _clearAllInternal() {
    for (final l in layers) {
      l.strokes.clear();
      l.cachedImage?.dispose();
      l.cachedImage = null;
    }
  }

  List<LayerSnapshot> _takeSnapshots() {
    return layers
        .map((l) => LayerSnapshot(
              id: l.id,
              name: l.name,
              visible: l.visible,
              opacity: l.opacity,
              blendMode: l.blendMode,
              maskMode: l.maskMode,
              glowSize: l.glowSize,
              glowStrength: l.glowStrength,
              strokes: List.from(l.strokes),
            ))
        .toList();
  }

  void _restoreSnapshots(List<LayerSnapshot> snaps) {
    for (final snap in snaps) {
      final idx = layers.indexWhere((l) => l.id == snap.id);
      if (idx >= 0) {
        layers[idx].strokes = List.from(snap.strokes);
        layers[idx].visible = snap.visible;
        layers[idx].opacity = snap.opacity;
        layers[idx].blendMode = snap.blendMode;
        _updateLayerCache(layers[idx]);
      }
    }
  }

  // ───── Layers management ─────
  void addLayer() {
    final l = DrawingLayer(id: _nextLayerId++, name: 'Layer $_nextLayerId');
    layers.add(l);
    activeLayerIndex = layers.length - 1;
    _recompose();
    notifyListeners();
  }

  void removeLayer(int id) {
    if (layers.length <= 1) return;
    final idx = layers.indexWhere((l) => l.id == id);
    if (idx < 0) return;
    layers[idx].cachedImage?.dispose();
    layers.removeAt(idx);
    if (activeLayerIndex >= layers.length) activeLayerIndex = layers.length - 1;
    _recompose();
    notifyListeners();
  }

  void selectLayer(int index) {
    activeLayerIndex = index.clamp(0, layers.length - 1);
    notifyListeners();
  }

  void toggleLayerVisibility(int id) {
    final l = layers.firstWhere((l) => l.id == id, orElse: () => layers.first);
    l.visible = !l.visible;
    _recompose();
    notifyListeners();
  }

  void reorderLayer(int fromIndex, int toIndex) {
    if (fromIndex == toIndex) return;
    final item = layers.removeAt(fromIndex);
    layers.insert(toIndex.clamp(0, layers.length), item);
    // adjust active
    if (activeLayerIndex == fromIndex) {
      activeLayerIndex = toIndex.clamp(0, layers.length - 1);
    }
    _recompose();
    notifyListeners();
  }

  void updateLayerSettings(int id,
      {String? name,
      double? opacity,
      BlendMode? blendMode,
      String? maskMode,
      double? glowSize,
      double? glowStrength}) {
    final idx = layers.indexWhere((l) => l.id == id);
    if (idx < 0) return;
    final l = layers[idx];
    if (name != null) l.name = name;
    if (opacity != null) l.opacity = opacity;
    if (blendMode != null) l.blendMode = blendMode;
    if (maskMode != null) l.maskMode = maskMode;
    if (glowSize != null) l.glowSize = glowSize;
    if (glowStrength != null) l.glowStrength = glowStrength;
    _recompose();
    notifyListeners();
  }

  // ───── Compositing ─────
  void _recompose() {
    // Compositing is done in the painter for simplicity
    notifyListeners();
  }

  // ───── Save ─────
  Future<Uint8List?> exportPng() async {
    final recorder = ui.PictureRecorder();
    final sz = Size(worldWidth.toDouble(), worldHeight.toDouble());
    final canvas = Canvas(recorder, Offset.zero & sz);

    // Background
    canvas.drawRect(Offset.zero & sz, Paint()..color = backgroundColor);

    // Compose layers
    for (final l in layers) {
      if (!l.visible) continue;
      if (l.cachedImage == null) continue;

      if (l.blendMode == BlendMode.plus) {
        // Glow: halo + core
        final blurPx = 2.0 + (l.glowSize / 100) * 24;
        final haloAlpha = (l.glowStrength / 100) * l.opacity;
        canvas.saveLayer(
            Offset.zero & sz,
            Paint()
              ..blendMode = BlendMode.plus
              ..color = Color.fromARGB((haloAlpha * 255).round(), 255, 255, 255)
              ..imageFilter =
                  ui.ImageFilter.blur(sigmaX: blurPx, sigmaY: blurPx));
        canvas.drawImage(l.cachedImage!, Offset.zero, Paint());
        canvas.restore();
        // Core
        canvas.saveLayer(
            Offset.zero & sz,
            Paint()
              ..blendMode = BlendMode.plus
              ..color =
                  Color.fromARGB((l.opacity * 255).round(), 255, 255, 255));
        canvas.drawImage(l.cachedImage!, Offset.zero, Paint());
        canvas.restore();
      } else if (l.maskMode == 'alpha') {
        canvas.saveLayer(
            Offset.zero & sz,
            Paint()
              ..blendMode = BlendMode.dstIn
              ..color =
                  Color.fromARGB((l.opacity * 255).round(), 255, 255, 255));
        canvas.drawImage(l.cachedImage!, Offset.zero, Paint());
        canvas.restore();
      } else if (l.maskMode == 'alpha-invert') {
        canvas.saveLayer(
            Offset.zero & sz,
            Paint()
              ..blendMode = BlendMode.dstOut
              ..color =
                  Color.fromARGB((l.opacity * 255).round(), 255, 255, 255));
        canvas.drawImage(l.cachedImage!, Offset.zero, Paint());
        canvas.restore();
      } else {
        canvas.saveLayer(
            Offset.zero & sz,
            Paint()
              ..blendMode = l.blendMode
              ..color =
                  Color.fromARGB((l.opacity * 255).round(), 255, 255, 255));
        canvas.drawImage(l.cachedImage!, Offset.zero, Paint());
        canvas.restore();
      }
    }

    final pic = recorder.endRecording();
    final img = await pic.toImage(worldWidth, worldHeight);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return byteData?.buffer.asUint8List();
  }
}

class _StampParams {
  final double size, angle, alpha, offX, offY, spacing;
  const _StampParams({
    required this.size,
    required this.angle,
    required this.alpha,
    required this.offX,
    required this.offY,
    required this.spacing,
  });
}

// Extend Matrix4 with a helper
extension Matrix4Ext on Matrix4 {
  Vector4 transform4(Vector4 v) {
    return Vector4(
      storage[0] * v.x + storage[4] * v.y + storage[8] * v.z + storage[12] * v.w,
      storage[1] * v.x + storage[5] * v.y + storage[9] * v.z + storage[13] * v.w,
      storage[2] * v.x + storage[6] * v.y + storage[10] * v.z + storage[14] * v.w,
      storage[3] * v.x + storage[7] * v.y + storage[11] * v.z + storage[15] * v.w,
    );
  }
}

class Vector4 {
  final double x, y, z, w;
  const Vector4(this.x, this.y, this.z, this.w);
}
