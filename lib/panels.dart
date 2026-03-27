import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'drawing_state.dart';
import 'models.dart';
import 'color_wheel.dart';

// ═══════════════════ TOOLBAR ═══════════════════
class AppToolbar extends StatelessWidget {
  const AppToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DrawingState>(builder: (ctx, state, _) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 32,
                    offset: const Offset(0, 10)),
              ],
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Color
                _ToolBtn(
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: state.colorPick.toColor(),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.black12),
                    ),
                  ),
                  onTap: () => _showColorModal(context, state),
                ),
                // Brush
                _ToolBtn(
                  child: const Icon(Icons.brush, size: 20),
                  onTap: () => _showBrushModal(context, state),
                ),
                // Layers
                _ToolBtn(
                  child: const Icon(Icons.layers, size: 20),
                  onTap: () => _showLayersPanel(context, state),
                ),
                // Undo
                _ToolBtn(
                  child: const Icon(Icons.undo, size: 20),
                  onTap: () => state.undo(),
                ),
                // Redo
                _ToolBtn(
                  child: const Icon(Icons.redo, size: 20),
                  onTap: () => state.redo(),
                ),
                // Clear
                _ToolBtn(
                  child: const Icon(Icons.delete_outline, size: 20),
                  onTap: () => state.clearAll(),
                ),
                // Save
                _ToolBtn(
                  child: const Icon(Icons.save_alt, size: 20),
                  onTap: () => _savePng(context, state),
                ),
                // Reset view
                _ToolBtn(
                  child: const Icon(Icons.crop_square, size: 20),
                  onTap: () {
                    final mq = MediaQuery.of(context);
                    state.resetCamera(mq.size);
                  },
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  void _showColorModal(BuildContext context, DrawingState state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _ColorModalBody(state: state),
    );
  }

  void _showBrushModal(BuildContext context, DrawingState state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _BrushModalBody(state: state),
    );
  }

  void _showLayersPanel(BuildContext context, DrawingState state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _LayersPanelBody(state: state),
    );
  }

  Future<void> _savePng(BuildContext context, DrawingState state) async {
    final bytes = await state.exportPng();
    if (bytes == null) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
          '${dir.path}/drawing_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved to ${file.path}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    }
  }
}

class _ToolBtn extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;

  const _ToolBtn({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black12),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

// ═══════════════════ COLOR MODAL ═══════════════════
class _ColorModalBody extends StatefulWidget {
  final DrawingState state;
  const _ColorModalBody({required this.state});
  @override
  State<_ColorModalBody> createState() => _ColorModalBodyState();
}

class _ColorModalBodyState extends State<_ColorModalBody> {
  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (ctx, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header('Color'),
              const SizedBox(height: 16),
              ColorWheelPicker(
                pick: widget.state.colorPick,
                onChanged: () {
                  widget.state.updateColorFromPick();
                  setState(() {});
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════ BRUSH MODAL ═══════════════════
class _BrushModalBody extends StatefulWidget {
  final DrawingState state;
  const _BrushModalBody({required this.state});
  @override
  State<_BrushModalBody> createState() => _BrushModalBodyState();
}

class _BrushModalBodyState extends State<_BrushModalBody>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  BrushSettings get b => widget.state.brush;

  void _update() {
    widget.state.updateBrush();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.80,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (ctx, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  _header('Brush'),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.casino, size: 18),
                    label: const Text('Random'),
                    onPressed: () {
                      widget.state.randomizeSeed();
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabCtrl,
              labelColor: Colors.black87,
              unselectedLabelColor: Colors.grey,
              tabs: const [
                Tab(text: 'Dynamics'),
                Tab(text: 'Shape'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _dynamicsTab(scrollController),
                  _shapeTab(scrollController),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _dynamicsTab(ScrollController sc) {
    return ListView(
      controller: sc,
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Dynamics'),
        _slider('Size', b.size, 6, 1024, '${b.size.round()} px', (v) {
          b.size = v;
          _update();
        }),
        _slider('Spacing', b.spacing * 100, 5, 100, '${(b.spacing * 100).round()}%',
            (v) {
          b.spacing = v / 100;
          _update();
        }),
        _slider('Flow', b.flow * 100, 5, 100, '${(b.flow * 100).round()}%', (v) {
          b.flow = v / 100;
          _update();
        }),
        _slider('Smoothing', b.smoothing * 100, 0, 90,
            '${(b.smoothing * 100).round()}%', (v) {
          b.smoothing = v / 100;
          _update();
        }),
        _slider('Angle smoothing', b.angleSmoothing * 100, 0, 90,
            '${(b.angleSmoothing * 100).round()}%', (v) {
          b.angleSmoothing = v / 100;
          _update();
        }),
        _slider('Scatter', b.scatter * 100, 0, 100, '${(b.scatter * 100).round()}%',
            (v) {
          b.scatter = v / 100;
          _update();
        }),
        _slider('Angle offset', b.angleOffsetDeg, -180, 180,
            '${b.angleOffsetDeg.round()}°', (v) {
          b.angleOffsetDeg = v;
          _update();
        }),
        SwitchListTile(
          title: const Text('Follow angle', style: TextStyle(fontSize: 13)),
          value: b.followAngle,
          onChanged: (v) {
            b.followAngle = v;
            _update();
          },
          dense: true,
        ),
        _blendDropdown(),
        const SizedBox(height: 16),
        _sectionTitle('Texture'),
        _slider('Softness', b.softness * 100, 0, 100,
            '${(b.softness * 100).round()}%', (v) {
          b.softness = v / 100;
          _update();
        }),
        _slider(
            'Feather', b.feather * 100, 0, 100, '${(b.feather * 100).round()}%',
            (v) {
          b.feather = v / 100;
          _update();
        }),
        _slider('Grain', b.grain * 100, 0, 100, '${(b.grain * 100).round()}%',
            (v) {
          b.grain = v / 100;
          _update();
        }),
        const SizedBox(height: 16),
        _sectionTitle('Jitter'),
        _slider('Size jitter', b.jitter.size * 100, 0, 50,
            '${(b.jitter.size * 100).round()}%', (v) {
          b.jitter.size = v / 100;
          _update();
        }),
        _slider('Angle jitter', b.jitter.angle, 0, 180,
            '${b.jitter.angle.round()}°', (v) {
          b.jitter.angle = v;
          _update();
        }),
        _slider('Opacity jitter', b.jitter.opacity * 100, 0, 100,
            '${(b.jitter.opacity * 100).round()}%', (v) {
          b.jitter.opacity = v / 100;
          _update();
        }),
        _slider('Spacing jitter', b.jitter.spacing * 100, 0, 50,
            '${(b.jitter.spacing * 100).round()}%', (v) {
          b.jitter.spacing = v / 100;
          _update();
        }),
      ],
    );
  }

  Widget _shapeTab(ScrollController sc) {
    final s = b.shape;
    return ListView(
      controller: sc,
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Shape'),
        _slider('Symmetry', s.symmetry.toDouble(), 2, 5, '${s.symmetry}', (v) {
          s.symmetry = v.round();
          _update();
        }),
        _slider('Complexity', s.complexity.toDouble(), 1, 30, '${s.complexity}',
            (v) {
          s.complexity = v.round();
          _update();
        }),
        _slider('Density', s.density * 100, 0, 100, '${(s.density * 100).round()}%',
            (v) {
          s.density = v / 100;
          _update();
        }),
        _slider(
            'Organic', s.organic * 100, 0, 100, '${(s.organic * 100).round()}%',
            (v) {
          s.organic = v / 100;
          _update();
        }),
        _slider('Core', s.core * 100, 0, 100, '${(s.core * 100).round()}%', (v) {
          s.core = v / 100;
          _update();
        }),
        const SizedBox(height: 16),
        _sectionTitle('Style'),
        _slider('Roundness', s.roundness * 100, 0, 100,
            '${(s.roundness * 100).round()}%', (v) {
          s.roundness = v / 100;
          _update();
        }),
        _slider('Shadow size', s.shadowSize * 100, 0, 100,
            '${(s.shadowSize * 100).round()}%', (v) {
          s.shadowSize = v / 100;
          _update();
        }),
        _slider('Shadow opacity', s.shadowOpacity * 100, 0, 100,
            '${(s.shadowOpacity * 100).round()}%', (v) {
          s.shadowOpacity = v / 100;
          _update();
        }),
      ],
    );
  }

  Widget _blendDropdown() {
    final modes = {
      BlendMode.srcOver: 'Normal',
      BlendMode.multiply: 'Multiply',
      BlendMode.screen: 'Screen',
      BlendMode.plus: 'Lighter / Add',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Text('Blend mode', style: TextStyle(fontSize: 13)),
          const Spacer(),
          DropdownButton<BlendMode>(
            value: b.blendMode,
            isDense: true,
            underline: const SizedBox(),
            items: modes.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13))))
                .toList(),
            onChanged: (v) {
              if (v != null) {
                b.blendMode = v;
                _update();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _slider(String label, double value, double min, double max,
      String display, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          Row(
            children: [
              Text(label, style: const TextStyle(fontSize: 13)),
              const Spacer(),
              Text(display,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════ LAYERS PANEL ═══════════════════
class _LayersPanelBody extends StatefulWidget {
  final DrawingState state;
  const _LayersPanelBody({required this.state});
  @override
  State<_LayersPanelBody> createState() => _LayersPanelBodyState();
}

class _LayersPanelBodyState extends State<_LayersPanelBody> {
  DrawingState get s => widget.state;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      minChildSize: 0.3,
      builder: (ctx, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  _header('Layers'),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () {
                      s.addLayer();
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),
            // Background color
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  const Text('Background', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _pickBackgroundColor(context),
                    child: Container(
                      width: 32,
                      height: 24,
                      decoration: BoxDecoration(
                        color: s.backgroundColor,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.black12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: ReorderableListView.builder(
                scrollController: scrollController,
                itemCount: s.layers.length,
                onReorder: (oldIdx, newIdx) {
                  // convert from reverse display order
                  final rOld = s.layers.length - 1 - oldIdx;
                  var rNew = s.layers.length - 1 - newIdx;
                  if (rOld < rNew) rNew++;
                  s.reorderLayer(rOld, rNew.clamp(0, s.layers.length));
                  setState(() {});
                },
                itemBuilder: (ctx, index) {
                  // Show topmost at top
                  final rIdx = s.layers.length - 1 - index;
                  final l = s.layers[rIdx];
                  final isActive = rIdx == s.activeLayerIndex;

                  return Container(
                    key: ValueKey(l.id),
                    margin:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: isActive
                          ? const Color(0xFFEEF4FF)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isActive
                            ? const Color(0xFFC6D4FF)
                            : Colors.black12,
                      ),
                    ),
                    child: ListTile(
                      dense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      title: Text(l.name,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          '${l.visible ? "" : "Hidden • "}'
                          '${_blendName(l.blendMode)} • ${(l.opacity * 100).round()}%',
                          style: const TextStyle(fontSize: 11)),
                      leading: Icon(
                        l.visible ? Icons.visibility : Icons.visibility_off,
                        size: 20,
                        color: l.visible ? Colors.green : Colors.grey,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.settings, size: 18),
                            onPressed: () => _showLayerSettings(context, l),
                          ),
                          const Icon(Icons.drag_handle, size: 18),
                        ],
                      ),
                      onTap: () {
                        s.selectLayer(rIdx);
                        setState(() {});
                      },
                      onLongPress: () {
                        s.toggleLayerVisibility(l.id);
                        setState(() {});
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _pickBackgroundColor(BuildContext context) {
    final colors = [
      Colors.white,
      Colors.black,
      const Color(0xFFF5F5F5),
      const Color(0xFF1A1A2E),
      const Color(0xFFE8D5B7),
      const Color(0xFFB0C4DE),
      const Color(0xFF2D2D2D),
    ];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Background Color', style: TextStyle(fontSize: 16)),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: colors.map((c) {
            return GestureDetector(
              onTap: () {
                s.backgroundColor = c;
                s.notifyListeners();
                setState(() {});
                Navigator.pop(ctx);
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black26),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showLayerSettings(BuildContext context, DrawingLayer l) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _LayerSettingsBody(state: s, layer: l, onUpdate: () => setState(() {})),
    );
  }

  String _blendName(BlendMode m) {
    switch (m) {
      case BlendMode.srcOver:
        return 'Normal';
      case BlendMode.multiply:
        return 'Multiply';
      case BlendMode.screen:
        return 'Screen';
      case BlendMode.overlay:
        return 'Overlay';
      case BlendMode.plus:
        return 'Add';
      case BlendMode.darken:
        return 'Darken';
      case BlendMode.lighten:
        return 'Lighten';
      case BlendMode.colorDodge:
        return 'Dodge';
      case BlendMode.colorBurn:
        return 'Burn';
      case BlendMode.difference:
        return 'Difference';
      default:
        return m.name;
    }
  }
}

// ═══════════════════ LAYER SETTINGS ═══════════════════
class _LayerSettingsBody extends StatefulWidget {
  final DrawingState state;
  final DrawingLayer layer;
  final VoidCallback onUpdate;
  const _LayerSettingsBody(
      {required this.state, required this.layer, required this.onUpdate});
  @override
  State<_LayerSettingsBody> createState() => _LayerSettingsBodyState();
}

class _LayerSettingsBodyState extends State<_LayerSettingsBody> {
  late TextEditingController _nameCtrl;
  DrawingLayer get l => widget.layer;
  DrawingState get s => widget.state;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: l.name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allModes = {
      BlendMode.srcOver: 'Normal',
      BlendMode.multiply: 'Multiply',
      BlendMode.screen: 'Screen',
      BlendMode.overlay: 'Overlay',
      BlendMode.darken: 'Darken',
      BlendMode.lighten: 'Lighten',
      BlendMode.colorDodge: 'Color Dodge',
      BlendMode.colorBurn: 'Color Burn',
      BlendMode.hardLight: 'Hard Light',
      BlendMode.softLight: 'Soft Light',
      BlendMode.difference: 'Difference',
      BlendMode.exclusion: 'Exclusion',
      BlendMode.hue: 'Hue',
      BlendMode.saturation: 'Saturation',
      BlendMode.color: 'Color',
      BlendMode.luminosity: 'Luminosity',
      BlendMode.plus: 'Add (Glow)',
    };

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header('Layer Settings'),
          const SizedBox(height: 16),
          // Name
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
                isDense: true),
            onChanged: (v) {
              s.updateLayerSettings(l.id, name: v);
              widget.onUpdate();
            },
          ),
          const SizedBox(height: 12),
          // Opacity
          Row(
            children: [
              const Text('Opacity', style: TextStyle(fontSize: 13)),
              Expanded(
                child: Slider(
                  value: l.opacity,
                  onChanged: (v) {
                    s.updateLayerSettings(l.id, opacity: v);
                    widget.onUpdate();
                    setState(() {});
                  },
                ),
              ),
              Text('${(l.opacity * 100).round()}%',
                  style: const TextStyle(fontSize: 12)),
            ],
          ),
          // Blend mode
          Row(
            children: [
              const Text('Blend', style: TextStyle(fontSize: 13)),
              const Spacer(),
              DropdownButton<BlendMode>(
                value: l.blendMode,
                isDense: true,
                items: allModes.entries
                    .map((e) => DropdownMenuItem(
                        value: e.key,
                        child:
                            Text(e.value, style: const TextStyle(fontSize: 13))))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    s.updateLayerSettings(l.id, blendMode: v);
                    widget.onUpdate();
                    setState(() {});
                  }
                },
              ),
            ],
          ),
          // Mask mode
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Mask', style: TextStyle(fontSize: 13)),
              const Spacer(),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'none', label: Text('None', style: TextStyle(fontSize: 11))),
                  ButtonSegment(value: 'alpha', label: Text('Alpha', style: TextStyle(fontSize: 11))),
                  ButtonSegment(value: 'alpha-invert', label: Text('Invert', style: TextStyle(fontSize: 11))),
                ],
                selected: {l.maskMode},
                onSelectionChanged: (v) {
                  s.updateLayerSettings(l.id, maskMode: v.first);
                  widget.onUpdate();
                  setState(() {});
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Delete
          if (s.layers.length > 1)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
                icon: const Icon(Icons.delete, size: 18),
                label: const Text('Delete Layer'),
                onPressed: () {
                  s.removeLayer(l.id);
                  widget.onUpdate();
                  Navigator.pop(context);
                },
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ═══════════════════ HELPERS ═══════════════════
Widget _header(String text) => Text(text,
    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700));

Widget _sectionTitle(String text) => Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(text,
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54)),
    );
