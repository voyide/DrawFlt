import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'drawing_state.dart';
import 'models.dart';

class DrawingCanvasWidget extends StatefulWidget {
  const DrawingCanvasWidget({super.key});

  @override
  State<DrawingCanvasWidget> createState() => _DrawingCanvasWidgetState();
}

class _DrawingCanvasWidgetState extends State<DrawingCanvasWidget> {
  final Map<int, Offset> _pointers = {};
  _GestureState? _gesture;
  bool _isDrawing = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<DrawingState>(
      builder: (context, state, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            if (!state.cameraInitialized) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                state.initCamera(Size(constraints.maxWidth, constraints.maxHeight));
              });
            }
            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) => _onPointerDown(e, state, constraints),
              onPointerMove: (e) => _onPointerMove(e, state),
              onPointerUp: (e) => _onPointerUp(e, state),
              onPointerCancel: (e) => _onPointerUp(e, state),
              onPointerSignal: (e) => _onPointerSignal(e, state),
              child: CustomPaint(
                painter: _CanvasPainter(state),
                size: Size(constraints.maxWidth, constraints.maxHeight),
              ),
            );
          },
        );
      },
    );
  }

  Offset _toWorld(Offset screen, DrawingState state) {
    final inv = state.screenToWorld;
    final x = inv.storage[0] * screen.dx +
        inv.storage[4] * screen.dy +
        inv.storage[12];
    final y = inv.storage[1] * screen.dx +
        inv.storage[5] * screen.dy +
        inv.storage[13];
    return Offset(x, y);
  }

  void _onPointerDown(PointerDownEvent e, DrawingState state, BoxConstraints c) {
    _pointers[e.pointer] = e.localPosition;

    if (_pointers.length == 2) {
      if (_isDrawing) {
        state.endStroke();
        _isDrawing = false;
      }
      _startGesture(state);
    } else if (_pointers.length == 1) {
      if (!state.cameraInitialized) {
        state.initCamera(Size(c.maxWidth, c.maxHeight));
      }
      _isDrawing = true;
      final wp = _toWorld(e.localPosition, state);
      state.beginStroke(wp);
    }
  }

  void _onPointerMove(PointerMoveEvent e, DrawingState state) {
    if (_pointers.containsKey(e.pointer)) {
      _pointers[e.pointer] = e.localPosition;
    }

    if (_pointers.length >= 2) {
      _updateGesture(state);
      _isDrawing = false;
    } else if (_pointers.length == 1 && _isDrawing) {
      final wp = _toWorld(e.localPosition, state);
      state.extendStroke(wp);
    }
  }

  void _onPointerUp(PointerEvent e, DrawingState state) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) {
      _gesture = null;
    }
    if (_pointers.isEmpty && _isDrawing) {
      state.endStroke();
      _isDrawing = false;
    }
  }

  void _onPointerSignal(PointerSignalEvent e, DrawingState state) {
    if (e is PointerScrollEvent) {
      final scale = e.scrollDelta.dy > 0 ? 0.92 : 1.08;
      final focus = e.localPosition;
      final delta = Matrix4.identity()
        ..translate(focus.dx, focus.dy)
        ..scale(scale, scale)
        ..translate(-focus.dx, -focus.dy);
      state.applyPanZoom(delta);
    }
  }

  void _startGesture(DrawingState state) {
    final pts = _pointers.values.toList();
    final c0 = Offset((pts[0].dx + pts[1].dx) / 2, (pts[0].dy + pts[1].dy) / 2);
    final dx = pts[1].dx - pts[0].dx, dy = pts[1].dy - pts[0].dy;
    _gesture = _GestureState(
      startMatrix: Matrix4.copy(state.worldToScreen),
      center: c0,
      startDist: sqrt(dx * dx + dy * dy),
      startAngle: atan2(dy, dx),
    );
  }

  void _updateGesture(DrawingState state) {
    if (_gesture == null || _pointers.length < 2) return;
    final pts = _pointers.values.toList();
    final c1 = Offset((pts[0].dx + pts[1].dx) / 2, (pts[0].dy + pts[1].dy) / 2);
    final dx = pts[1].dx - pts[0].dx, dy = pts[1].dy - pts[0].dy;
    final d1 = sqrt(dx * dx + dy * dy);
    if (_gesture!.startDist < 5) return;
    final a1 = atan2(dy, dx);

    final scale = d1 / _gesture!.startDist;
    final rot = a1 - _gesture!.startAngle;

    final delta = Matrix4.identity()
      ..translate(c1.dx, c1.dy)
      ..rotateZ(rot)
      ..scale(scale, scale)
      ..translate(-_gesture!.center.dx, -_gesture!.center.dy);

    state.worldToScreen = delta * _gesture!.startMatrix;
    state.screenToWorld = Matrix4.copy(state.worldToScreen)..invert();
    state.notifyListeners();
  }
}

class _GestureState {
  final Matrix4 startMatrix;
  final Offset center;
  final double startDist;
  final double startAngle;
  _GestureState(
      {required this.startMatrix,
      required this.center,
      required this.startDist,
      required this.startAngle});
}

class _CanvasPainter extends CustomPainter {
  final DrawingState state;

  _CanvasPainter(this.state) : super(repaint: state);

  @override
  void paint(Canvas canvas, Size size) {
    // ── Grid background ──
    _drawGrid(canvas, size);

    // ── Apply camera transform ──
    canvas.save();
    canvas.transform(state.worldToScreen.storage);

    final worldRect = Rect.fromLTWH(
        0, 0, state.worldWidth.toDouble(), state.worldHeight.toDouble());

    // ── Background color ──
    canvas.drawRect(worldRect, Paint()..color = state.backgroundColor);

    // ── Draw each layer ──
    for (int i = 0; i < state.layers.length; i++) {
      final l = state.layers[i];
      if (!l.visible) continue;

      final layerPaint = Paint()
        ..color = Color.fromARGB((l.opacity * 255).round(), 255, 255, 255);

      if (l.maskMode == 'alpha') {
        layerPaint.blendMode = BlendMode.dstIn;
      } else if (l.maskMode == 'alpha-invert') {
        layerPaint.blendMode = BlendMode.dstOut;
      } else {
        layerPaint.blendMode = l.blendMode;
      }

      canvas.saveLayer(worldRect, layerPaint);

      // Draw cached content
      if (l.cachedImage != null) {
        canvas.drawImage(l.cachedImage!, Offset.zero, Paint());
      }

      // Draw active stroke on active layer
      if (i == state.activeLayerIndex && state.activeStroke != null) {
        _paintStroke(canvas, state.activeStroke!);
      }

      canvas.restore();
    }

    canvas.restore(); // camera
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

  void _drawGrid(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFFE9E9EC);
    canvas.drawRect(Offset.zero & size, bg);

    final line = Paint()
      ..color = const Color(0x12000000)
      ..strokeWidth = 1;
    const step = 32.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter old) => true;
}
