import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/audio.dart';
import '../ui.dart';
import 'winamp.dart';

/// Пресеты шейдера shaders/milkdrop.frag (по порядку).
const milkdropPresets = [
  'Geiss — Tunnel of Echoes',
  'Krash — Kaleidoscope Dreams',
  'Rovastar — Spiral Bloom',
  'Unchained — Liquid Oscilloscope',
  'Zylot — Starburst',
];

/// Управление видом MilkDrop снаружи (кнопка «следующий пресет»).
class MilkdropController extends ChangeNotifier {
  int _preset = 0;
  int get preset => _preset;
  void next() {
    _preset = (_preset + 1) % milkdropPresets.length;
    notifyListeners();
  }

  void set(int i) {
    _preset = i % milkdropPresets.length;
    notifyListeners();
  }
}

/// Визуализация MilkDrop: шейдер на видеокарте, кадры — через repaint (без перестройки виджетов).
/// Сам меняет пресет каждые 20 с с плавным переходом. Звука плеер iOS не отдаёт — «удары» идут
/// ритмичным генератором, пока играет музыка.
class MilkdropView extends StatefulWidget {
  /// Загрузить шейдер заранее (при включении Эховампа) — окно MilkDrop откроется без чёрного кадра.
  static Future<ui.FragmentProgram?> preload() => _MilkdropViewState._load();

  final MilkdropController? controller;
  final bool autoSwitch;
  const MilkdropView({super.key, this.controller, this.autoSwitch = true});

  @override
  State<MilkdropView> createState() => _MilkdropViewState();
}

class _MilkdropViewState extends State<MilkdropView> with SingleTickerProviderStateMixin {
  static Future<ui.FragmentProgram?>? _program;
  static ui.FragmentProgram? _ready; // уже загружен — берём сразу, без чёрного кадра
  static Future<ui.FragmentProgram?> _load() => _program ??= ui.FragmentProgram.fromAsset('shaders/milkdrop.frag')
      .then<ui.FragmentProgram?>((p) => _ready = p)
      .catchError((_) => null);
  ui.FragmentShader? _shader;
  late final Ticker _ticker;
  final _frame = ValueNotifier<int>(0);
  late final MilkdropController _c = widget.controller ?? MilkdropController();
  Duration _prev = Duration.zero;
  double _time = 0, _energy = 0, _beat = 0, _mix = 1, _since = 0;
  int _a = 0, _b = 0;
  bool _playing = false;
  StreamSubscription<bool>? _sub;

  @override
  void initState() {
    super.initState();
    _shader = _ready?.fragmentShader();
    if (_shader == null) {
      _load().then((p) {
        if (mounted && p != null && _shader == null) setState(() => _shader = p.fragmentShader());
      });
    }
    _a = _b = _c.preset;
    _c.addListener(_onPreset);
    _sub = audio.player.playingStream.listen((v) => _playing = v);
    _ticker = createTicker(_tick)..start();
  }

  void _onPreset() {
    if (_c.preset == _b) return;
    _a = _mix < 0.5 ? _a : _b;
    _b = _c.preset;
    _mix = 0;
    _since = 0;
  }

  void _tick(Duration now) {
    final dt = ((now - _prev).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _prev = now;
    _energy += ((_playing ? 1.0 : 0.15) - _energy) * (1 - math.exp(-dt * 2));
    // «бочка» ~124 BPM: короткий импульс, быстро гаснет
    final phase = (_time * 2.07) % 1.0;
    final kick = _playing ? math.exp(-phase * 9) : 0.0;
    _beat += (kick - _beat) * (kick > _beat ? 0.7 : 0.25);
    _time += dt * (0.6 + 0.7 * _energy);
    if (_mix < 1) _mix = math.min(1, _mix + dt / 2.5);
    _since += dt;
    if (widget.autoSwitch && _since > 20 && _mix >= 1) _c.next();
    _frame.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _sub?.cancel();
    _c.removeListener(_onPreset);
    if (widget.controller == null) _c.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _shader;
    if (s == null) return const ColoredBox(color: Colors.black);
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _MilkPainter(_frame, s, () => [_time, _energy, _beat, _a.toDouble(), _b.toDouble(), _mix]),
      ),
    );
  }
}

class _MilkPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final List<double> Function() values;
  _MilkPainter(Listenable frame, this.shader, this.values) : super(repaint: frame);

  @override
  void paint(Canvas canvas, Size size) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height);
    final v = values();
    for (var i = 0; i < v.length; i++) {
      shader.setFloat(2 + i, v[i]);
    }
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_MilkPainter old) => old.shader != shader;
}

/// Окно MilkDrop на весь экран (кнопка «MILKDROP» в плеере Эховампа): нажатие — следующий пресет,
/// его название появляется зелёным на пару секунд, как в Winamp.
class MilkdropScreen extends StatefulWidget {
  const MilkdropScreen({super.key});

  @override
  State<MilkdropScreen> createState() => _MilkdropScreenState();
}

class _MilkdropScreenState extends State<MilkdropScreen> {
  final _c = MilkdropController();
  bool _showName = true;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _c.addListener(_flash);
    _flash();
  }

  void _flash() {
    _hide?.cancel();
    setState(() => _showName = true);
    _hide = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _showName = false);
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(children: [
          WaBevel(
            padding: EdgeInsets.all(context.u(4)),
            child: WaTitleBar(
              title: 'MILKDROP',
              leading: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.close_rounded, color: Wa.text, size: context.u(22)),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _c.next,
              child: Stack(fit: StackFit.expand, children: [
                MilkdropView(controller: _c),
                Positioned(
                  left: context.u(12),
                  right: context.u(12),
                  top: context.u(12),
                  child: AnimatedOpacity(
                    opacity: _showName ? 1 : 0,
                    duration: const Duration(milliseconds: 400),
                    child: ListenableBuilder(
                      listenable: _c,
                      builder: (context, _) => Text(
                        '${_c.preset + 1}. ${milkdropPresets[_c.preset]}',
                        style: Wa.mono.copyWith(
                          color: Wa.green,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: context.u(14),
                  child: Text('нажмите — следующий пресет',
                      textAlign: TextAlign.center,
                      style: Wa.mono.copyWith(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
