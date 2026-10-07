import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/audio.dart';
import '../services/store.dart';
import '../ui.dart';
import 'milkdrop_engine.dart';
import 'milkdrop_words.dart';
import 'winamp.dart';

/// Управление MilkDrop снаружи: пресеты (135, как на ПК), режим смены. Слушатели узнают о смене пресета
/// (в том числе автоматической) — чтобы показать его название.
class MilkdropController extends ChangeNotifier {
  final MilkdropEngine engine;
  MilkdropController({int? start}) : engine = MilkdropEngine(start: start);
  int _shown = -1;

  String get name => engine.name;
  int get index => engine.index;
  MdMode get mode => engine.mode;

  void next() {
    engine.next();
    notifyListeners();
  }

  void prev() {
    engine.prev();
    notifyListeners();
  }

  void cycleMode() {
    engine.mode = MdMode.values[(engine.mode.index + 1) % MdMode.values.length];
    notifyListeners();
  }

  void _checkAuto() {
    if (_shown != engine.index) {
      _shown = engine.index;
      notifyListeners();
    }
  }
}

/// MilkDrop как на ПК, на видеокарте: буфер обратной связи (прошлый кадр → зум/поворот/варп → затухание),
/// поверх — волна и кольца от ударов; на экран — с цветовым ремапом. Шаг — 30 раз в секунду (как на ПК),
/// буфер ~280 px по ширине и растягивается со сглаживанием — картинка мягкая, а телефон не греется.
class MilkdropView extends StatefulWidget {
  /// Загрузить шейдеры заранее (при включении Эховампа) — окно MilkDrop откроется без чёрного кадра.
  static Future<void> preload() => _MilkdropViewState._load();

  /// Для тестов/скриншотов: «музыка играет» без плеера.
  static bool debugPlaying = false;

  final MilkdropController? controller;
  const MilkdropView({super.key, this.controller});

  @override
  State<MilkdropView> createState() => _MilkdropViewState();
}

class _MilkdropViewState extends State<MilkdropView> with SingleTickerProviderStateMixin {
  static Future<void>? _loading;
  static ui.FragmentProgram? _warpP, _compP; // уже загружены — берём сразу
  static Future<void> _load() => _loading ??= Future.wait([
        ui.FragmentProgram.fromAsset('shaders/md_warp.frag').then((p) => _warpP = p),
        ui.FragmentProgram.fromAsset('shaders/md_comp.frag').then((p) => _compP = p),
      ]).catchError((_) => <ui.FragmentProgram>[]);

  ui.FragmentShader? _warp, _comp;
  late final Ticker _ticker;
  final _frame = ValueNotifier<int>(0);
  late final MilkdropController _c = widget.controller ?? MilkdropController();
  ui.Image? _buf;
  Size _bufSize = Size.zero;
  double _aspect = 0.5, _acc = 0;
  Duration _prev = Duration.zero;
  bool _playing = false;
  StreamSubscription<bool>? _sub;

  @override
  void initState() {
    super.initState();
    _takeShaders();
    if (_warp == null) {
      _load().then((_) {
        if (mounted && _warp == null) setState(_takeShaders);
      });
    }
    _sub = audio.player.playingStream.listen((v) => _playing = v);
    _ticker = createTicker(_tick)..start();
  }

  void _takeShaders() {
    if (_warpP != null && _compP != null) {
      _warp = _warpP!.fragmentShader();
      _comp = _compP!.fragmentShader();
    }
  }

  void _tick(Duration now) {
    var dt = (now - _prev).inMicroseconds / 1e6;
    _prev = now;
    if (dt <= 0 || dt > 0.25) dt = 1 / 60;
    _acc += dt;
    if (_acc < 1 / 31 || _warp == null) return; // шаг физики и буфера — 30 раз в секунду
    final step = math.min(_acc, 0.1);
    _acc = 0;
    _render(step);
    _c._checkAuto();
    _frame.value++;
  }

  /// Шаг: прошлый кадр через md_warp.frag → волна и кольца поверх → новый кадр (картинка на видеокарте).
  void _render(double dt) {
    final w = 280.0, h = (280 / _aspect).roundToDouble().clamp(120.0, 900.0);
    if (_bufSize != Size(w, h)) {
      _buf?.dispose();
      _buf = null;
      _bufSize = Size(w, h);
    }
    final e = _c.engine;
    e.step(dt, _playing || MilkdropView.debugPlaying, w / h);
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec, Offset.zero & _bufSize);
    final prev = _buf;
    if (prev != null) {
      final u = e.warpUniforms(dt, w, h);
      for (var i = 0; i < u.length; i++) {
        _warp!.setFloat(i, u[i]);
      }
      _warp!.setImageSampler(0, prev);
      canvas.drawRect(Offset.zero & _bufSize, Paint()..shader = _warp);
    } else {
      canvas.drawRect(Offset.zero & _bufSize, Paint()..color = Colors.black);
    }
    final d = MdWaveDrawer(e, canvas, w, h);
    d.draw();
    d.rings(dt);
    final pic = rec.endRecording();
    _buf = pic.toImageSync(w.toInt(), h.toInt());
    pic.dispose();
    prev?.dispose();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _sub?.cancel();
    if (widget.controller == null) _c.dispose();
    _frame.dispose();
    _buf?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_comp == null) return const ColoredBox(color: Colors.black);
    return LayoutBuilder(builder: (context, box) {
      if (box.maxHeight > 0 && box.maxWidth.isFinite && box.maxHeight.isFinite) {
        _aspect = (box.maxWidth / box.maxHeight).clamp(0.3, 3.0);
      }
      return Stack(fit: StackFit.expand, children: [
        RepaintBoundary(
          child: CustomPaint(size: Size.infinite, painter: _CompPainter(_frame, _comp!, () => _buf, _c.engine)),
        ),
        // слова текста песни — ПОВЕРХ картинки (как на ПК), кнопка «ТЕКСТ» включает/выключает
        ListenableBuilder(
          listenable: Store.instance,
          builder: (context, _) => Store.instance.milkdropText
              ? RepaintBoundary(child: MilkdropWords(frame: _frame, hue: () => _c.engine.hue))
              : const SizedBox.shrink(),
        ),
      ]);
    });
  }
}

/// Вывод буфера на экран через md_comp.frag (ремап цвета; при смене пресета — плавно).
class _CompPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final ui.Image? Function() image;
  final MilkdropEngine e;
  _CompPainter(Listenable frame, this.shader, this.image, this.e) : super(repaint: frame);

  @override
  void paint(Canvas canvas, Size size) {
    final img = image();
    if (img == null) {
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
      return;
    }
    final k = e.blend * e.blend * (3 - 2 * e.blend);
    final v = [size.width, size.height, e.t, e.hue, e.remapFrom.toDouble(), e.p['remap']!, k];
    for (var i = 0; i < v.length; i++) {
      shader.setFloat(i, v[i]);
    }
    shader.setImageSampler(0, img);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_CompPainter old) => old.shader != shader;
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
            child: Row(children: [
              Expanded(
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
              // «ТЕКСТ»: строки текста песни вжигаются в картинку (лампочка — вкл/выкл)
              ListenableBuilder(
                listenable: Store.instance,
                builder: (context, _) {
                  final on = Store.instance.milkdropText;
                  return GestureDetector(
                    onTap: () => Store.instance.setMilkdropText(!on),
                    child: WaBevel(
                      color: Wa.btn,
                      padding: EdgeInsets.symmetric(horizontal: context.u(8), vertical: context.u(6)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(width: 6, height: 6, color: on ? Wa.green : Wa.greenDim),
                        const SizedBox(width: 5),
                        Text('ТЕКСТ',
                            style: Wa.mono.copyWith(color: Wa.text, fontSize: 10, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  );
                },
              ),
            ]),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _c.next,
              // свайп влево — следующий, вправо — прошлый; долгое нажатие — режим смены (авто / на удар / замок)
              onHorizontalDragEnd: (d) => (d.primaryVelocity ?? 0) > 0 ? _c.prev() : _c.next(),
              onLongPress: _c.cycleMode,
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
                        '${_c.index + 1}/${mdPresets.length}  ${_c.name}\n'
                        '${switch (_c.mode) { MdMode.auto => 'AUTO', MdMode.beat => 'BEAT', MdMode.lock => 'LOCK' }}',
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
                  child: Text('нажатие / свайп — пресет · удерживать — режим',
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
