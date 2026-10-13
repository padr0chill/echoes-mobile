import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../glass.dart';
import '../i18n.dart';
import '../models.dart';
import '../services/audio.dart';
import '../ui.dart';
import '../widgets.dart';

/// Мини-игры по плейлисту (меню «…» плейлиста).
void openSnake(BuildContext context, List<Track> tracks) => _open(context, SnakeGame(tracks: tracks));
void openGuess(BuildContext context, List<Track> tracks) => _open(context, GuessGame(tracks: tracks));

void _open(BuildContext context, Widget game) {
  final list = game is SnakeGame ? game.tracks : (game as GuessGame).tracks;
  if (list.length < 4) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr('Для игры нужно хотя бы 4 трека в плейлисте'))));
    return;
  }
  audio.pause(); // основной плеер молчит, пока идёт игра
  Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => game));
}

/// Второй плеер для отрывков: один на игру, источники готовятся заранее.
class _Snippets {
  final player = AudioPlayer();
  final _ready = <String, Future<AudioSource?>>{};
  String? playing;
  StreamSubscription<Duration>? _stopSub;

  Future<AudioSource?> prepare(Track t) => _ready[t.id] ??=
      audio.snippetSource(t).then<AudioSource?>((s) => s).timeout(const Duration(seconds: 15)).catchError((_) => null);

  /// Играть трек с позиции from; seconds — остановиться через столько секунд звука (null — играть дальше).
  Future<bool> play(Track t, {Duration from = Duration.zero, double? seconds}) async {
    final src = await prepare(t);
    if (src == null) return false;
    _stopSub?.cancel();
    try {
      if (playing != t.id) {
        await player.setAudioSource(src, initialPosition: from);
        playing = t.id;
      } else {
        await player.seek(from);
      }
      if (seconds != null) {
        final end = from + Duration(milliseconds: (seconds * 1000).round());
        _stopSub = player.positionStream.listen((p) {
          if (p >= end) {
            player.pause();
            _stopSub?.cancel();
          }
        });
      }
      unawaited(player.play());
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    _stopSub?.cancel();
    await player.pause();
  }

  void dispose() {
    _stopSub?.cancel();
    player.dispose();
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Змейка: ешь треки — у трека рядом с головой играет отрывок
// ════════════════════════════════════════════════════════════════════════════

class SnakeGame extends StatefulWidget {
  final List<Track> tracks;
  const SnakeGame({super.key, required this.tracks});

  @override
  State<SnakeGame> createState() => _SnakeGameState();
}

class _SnakeGameState extends State<SnakeGame> {
  static const cols = 15, rows = 21;
  final _rnd = math.Random();
  final _snip = _Snippets();
  late List<Track> _deck;
  List<math.Point<int>> _snake = [];
  math.Point<int> _dir = const math.Point(1, 0);
  math.Point<int>? _nextDir;
  math.Point<int>? _food;
  Track? _foodTrack;
  final _eaten = <Track>[];
  Timer? _timer;
  bool _over = false, _started = false;
  Track? _near; // трек, чей отрывок играет

  @override
  void initState() {
    super.initState();
    _deck = [...widget.tracks]..shuffle(_rnd);
    _reset();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _snip.dispose();
    super.dispose();
  }

  void _reset() {
    _snake = [const math.Point(5, 10), const math.Point(4, 10), const math.Point(3, 10)];
    _dir = const math.Point(1, 0);
    _nextDir = null;
    _eaten.clear();
    _over = false;
    _started = false;
    _near = null;
    _snip.stop();
    _spawn();
  }

  void _spawn() {
    final free = <math.Point<int>>[
      for (var x = 1; x < cols - 1; x++)
        for (var y = 1; y < rows - 1; y++)
          if (!_snake.contains(math.Point(x, y))) math.Point(x, y)
    ];
    _food = free[_rnd.nextInt(free.length)];
    if (_deck.isEmpty) _deck = [...widget.tracks]..shuffle(_rnd);
    _foodTrack = _deck.removeLast();
    _snip.prepare(_foodTrack!); // отрывок готовится, пока змейка ползёт
  }

  void _start() {
    if (_started) return;
    setState(() => _started = true);
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    // быстрее с каждым съеденным треком
    final ms = (190 - _eaten.length * 6).clamp(85, 190);
    _timer = Timer.periodic(Duration(milliseconds: ms), (_) => _tick());
  }

  void _turn(math.Point<int> d) {
    if (_over) return;
    final cur = _nextDir ?? _dir;
    if (cur.x + d.x == 0 && cur.y + d.y == 0) return; // назад нельзя
    _nextDir = d;
    _start();
  }

  void _tick() {
    if (_nextDir != null) {
      _dir = _nextDir!;
      _nextDir = null;
    }
    final head = _snake.first + _dir;
    if (head.x < 0 || head.y < 0 || head.x >= cols || head.y >= rows || _snake.contains(head)) {
      _timer?.cancel();
      HapticFeedback.heavyImpact();
      setState(() => _over = true);
      return;
    }
    final grow = head == _food;
    setState(() {
      _snake = [head, ..._snake];
      if (!grow) _snake.removeLast();
    });
    if (grow) {
      HapticFeedback.mediumImpact();
      _eaten.add(_foodTrack!);
      _spawn();
      _schedule();
    }
    // рядом с треком (≤ 4 клеток) — играет его отрывок с середины песни
    final f = _food!;
    final dist = (head.x - f.x).abs() + (head.y - f.y).abs();
    final t = _foodTrack!;
    if (dist <= 4 && _near != t) {
      _near = t;
      final from = Duration(seconds: t.seconds > 60 ? (t.seconds * 0.35).round() : 20);
      _snip.play(t, from: from);
    } else if (dist > 7 && _near != null && !grow) {
      _near = null;
      _snip.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6);
    return Ambient(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(tr('Змейка')),
          actions: [
            Center(
              child: Padding(
                padding: EdgeInsets.only(right: context.u(16)),
                child: Text(tr('Съедено: {0}', [_eaten.length]),
                    style: TextStyle(fontWeight: FontWeight.w800, color: context.accent)),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(children: [
            Expanded(
              child: GestureDetector(
                onTap: _start,
                onPanEnd: (d) {
                  final v = d.velocity.pixelsPerSecond;
                  if (v.distance < 80) return;
                  _turn(v.dx.abs() > v.dy.abs() ? math.Point(v.dx > 0 ? 1 : -1, 0) : math.Point(0, v.dy > 0 ? 1 : -1));
                },
                child: Center(
                  child: AspectRatio(
                    aspectRatio: cols / rows,
                    child: LayoutBuilder(builder: (context, c) {
                      final cell = c.maxWidth / cols;
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(context.r(18)),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(context.r(18)),
                          child: Stack(children: [
                            CustomPaint(
                                size: Size.infinite, painter: _SnakePainter(_snake, _dir, cell, context.accent)),
                            if (_food != null && _foodTrack != null)
                              Positioned(
                                left: _food!.x * cell - cell * 0.25,
                                top: _food!.y * cell - cell * 0.25,
                                child: _Food(track: _foodTrack!, size: cell * 1.5, active: _near == _foodTrack),
                              ),
                            if (!_started && !_over)
                              Center(
                                child: Text(tr('Свайпните, чтобы начать'),
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                              ),
                            if (_over)
                              Container(
                                color: Colors.black.withValues(alpha: 0.6),
                                alignment: Alignment.center,
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  Text(tr('Игра окончена'),
                                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                                  SizedBox(height: context.u(6)),
                                  Text(tr('Съедено: {0}', [_eaten.length]), style: TextStyle(color: dim)),
                                  SizedBox(height: context.u(16)),
                                  FilledButton(
                                    onPressed: () => setState(_reset),
                                    child: Text(tr('Ещё раз'), style: const TextStyle(color: Colors.black)),
                                  ),
                                  if (_eaten.isNotEmpty)
                                    TextButton(
                                      onPressed: () {
                                        for (final t in _eaten) {
                                          audio.addToQueue(t);
                                        }
                                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                            content: Text(tr('Съеденные треки — в очереди ({0})', [_eaten.length]))));
                                      },
                                      child: Text(tr('Съеденное — в очередь')),
                                    ),
                                ]),
                              ),
                          ]),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
            // что играет
            SizedBox(
              height: context.u(44),
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _near == null
                      ? Text(tr('Подползите к треку — заиграет отрывок'),
                          key: const ValueKey('hint'), style: TextStyle(color: dim))
                      : Row(key: ValueKey(_near!.id), mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.graphic_eq_rounded, color: context.accent),
                          SizedBox(width: context.u(6)),
                          ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
                            child: Text('${_near!.title} — ${_near!.artist}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ]),
                ),
              ),
            ),
            // крестовина
            Padding(
              padding: EdgeInsets.only(bottom: context.u(10)),
              child: Column(children: [
                _Pad(icon: Icons.keyboard_arrow_up_rounded, onTap: () => _turn(const math.Point(0, -1))),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _Pad(icon: Icons.keyboard_arrow_left_rounded, onTap: () => _turn(const math.Point(-1, 0))),
                  SizedBox(width: context.u(64)),
                  _Pad(icon: Icons.keyboard_arrow_right_rounded, onTap: () => _turn(const math.Point(1, 0))),
                ]),
                _Pad(icon: Icons.keyboard_arrow_down_rounded, onTap: () => _turn(const math.Point(0, 1))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Pad extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _Pad({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.all(context.u(2)),
        child: GlassIconButton(icon: icon, size: context.u(56), onTap: onTap),
      );
}

/// «Еда» — круглая обложка трека; пока играет её отрывок — пульсирует.
class _Food extends StatefulWidget {
  final Track track;
  final double size;
  final bool active;
  const _Food({required this.track, required this.size, required this.active});

  @override
  State<_Food> createState() => _FoodState();
}

class _FoodState extends State<_Food> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final k = widget.active ? 1 + 0.12 * _pulse.value : 1.0;
        return Transform.scale(
          scale: k,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: context.accent.withValues(alpha: widget.active ? 0.8 : 0.35),
                    blurRadius: widget.active ? 18 : 8),
              ],
              border: Border.all(color: context.accent, width: 2),
            ),
            child: ClipOval(child: child),
          ),
        );
      },
      child: Cover(track: widget.track, size: widget.size, radius: 0),
    );
  }
}

class _SnakePainter extends CustomPainter {
  final List<math.Point<int>> snake;
  final math.Point<int> dir;
  final double cell;
  final Color color;
  _SnakePainter(this.snake, this.dir, this.cell, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    // лёгкая сетка
    final grid = Paint()..color = Colors.white.withValues(alpha: 0.035);
    for (var x = 0; x * cell < size.width; x++) {
      for (var y = 0; y * cell < size.height; y++) {
        if ((x + y).isEven) canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), grid);
      }
    }
    final n = snake.length;
    for (var i = n - 1; i >= 0; i--) {
      final p = snake[i];
      final k = 1 - i / math.max(1, n) * 0.55;
      final c = Color.lerp(color.withValues(alpha: 0.45), color, k)!;
      final r = Rect.fromLTWH(p.x * cell + 1.5, p.y * cell + 1.5, cell - 3, cell - 3);
      canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(cell * (i == 0 ? 0.45 : 0.3))), Paint()..color = c);
    }
    // глаза
    final h = snake.first;
    final cx = h.x * cell + cell / 2, cy = h.y * cell + cell / 2;
    final px = -dir.y.toDouble(), py = dir.x.toDouble();
    for (final s in [-1, 1]) {
      final e = Offset(cx + dir.x * cell * 0.18 + px * s * cell * 0.2, cy + dir.y * cell * 0.18 + py * s * cell * 0.2);
      canvas.drawCircle(e, cell * 0.12, Paint()..color = Colors.white);
      canvas.drawCircle(
          e + Offset(dir.x * cell * 0.04, dir.y * cell * 0.04), cell * 0.06, Paint()..color = Colors.black);
    }
  }

  @override
  bool shouldRepaint(_SnakePainter old) => true;
}

// ════════════════════════════════════════════════════════════════════════════
//  Угадай песню по первым секундам: 1 → 2 → 3 → 4 → 5 → 6 с
// ════════════════════════════════════════════════════════════════════════════

class GuessGame extends StatefulWidget {
  final List<Track> tracks;
  const GuessGame({super.key, required this.tracks});

  @override
  State<GuessGame> createState() => _GuessGameState();
}

class _GuessGameState extends State<GuessGame> {
  static const rounds = 10;
  static const steps = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0];
  final _rnd = math.Random();
  final _snip = _Snippets();
  late List<Track> _order;
  int _round = 0, _step = 0, _score = 0;
  List<Track> _options = [];
  Track? _picked;
  bool _loading = true, _failed = false;
  final _results = <(Track, int)>[]; // трек, очки

  Track get _answer => _order[_round];
  bool get _revealed => _picked != null || _step >= steps.length;

  @override
  void initState() {
    super.initState();
    _order = ([...widget.tracks]..shuffle(_rnd)).take(rounds).toList();
    _newRound();
  }

  @override
  void dispose() {
    _snip.dispose();
    super.dispose();
  }

  Future<void> _newRound() async {
    final t = _answer;
    final others = widget.tracks.where((x) => x.id != t.id && x.title != t.title).toList()..shuffle(_rnd);
    setState(() {
      _step = 0;
      _picked = null;
      _options = [t, ...others.take(3)]..shuffle(_rnd);
      _loading = true;
      _failed = false;
    });
    // следующий раунд готовится заранее
    if (_round + 1 < _order.length) _snip.prepare(_order[_round + 1]);
    final ok = await _snip.prepare(t) != null;
    if (!mounted || _answer != t) return;
    setState(() {
      _loading = false;
      _failed = !ok;
    });
    if (ok) _listen();
  }

  void _listen() => _snip.play(_answer, seconds: steps[_step.clamp(0, steps.length - 1)]);

  void _skip() {
    if (_revealed) return;
    setState(() => _step++);
    if (_step < steps.length) {
      _listen();
    } else {
      _finishRound(0);
    }
  }

  void _pick(Track t) {
    if (_revealed) return;
    final right = t.id == _answer.id;
    HapticFeedback.mediumImpact();
    setState(() => _picked = t);
    _finishRound(right ? steps.length - _step : 0);
  }

  void _finishRound(int pts) {
    _score += pts;
    _results.add((_answer, pts));
    // показать ответ — песня играет дальше
    _snip.play(_answer, from: Duration.zero);
  }

  void _next() {
    _snip.stop();
    if (_round + 1 >= _order.length) {
      setState(() => _round = _order.length);
      return;
    }
    setState(() => _round++);
    _newRound();
  }

  @override
  Widget build(BuildContext context) {
    final done = _round >= _order.length;
    return Ambient(
      image: !done && _revealed ? _answer.cover : null,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(tr('Угадай песню')),
          actions: [
            Center(
              child: Padding(
                padding: EdgeInsets.only(right: context.u(16)),
                child: Text(tr('Очки: {0}', [_score]),
                    style: TextStyle(fontWeight: FontWeight.w800, color: context.accent)),
              ),
            ),
          ],
        ),
        body: SafeArea(child: done ? _summary(context) : _game(context)),
      ),
    );
  }

  Widget _game(BuildContext context) {
    final dim = Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6);
    final t = _answer;
    final right = _picked?.id == t.id;
    return ListView(padding: EdgeInsets.all(context.u(16)), children: [
      Text(tr('Раунд {0} из {1}', [_round + 1, _order.length]),
          textAlign: TextAlign.center, style: TextStyle(color: dim)),
      SizedBox(height: context.u(14)),
      // обложка: скрыта, пока не угадали
      Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: _revealed
              ? Cover(key: ValueKey('c${t.id}'), track: t, size: context.u(200), radius: context.u(18), big: true)
              : Container(
                  key: const ValueKey('q'),
                  width: context.u(200),
                  height: context.u(200),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(context.u(18)),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: Icon(Icons.question_mark_rounded, size: context.u(80), color: context.accent),
                ),
        ),
      ),
      SizedBox(height: context.u(10)),
      if (_revealed)
        Column(children: [
          Text(t.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          Text(t.artist, textAlign: TextAlign.center, style: TextStyle(color: dim)),
          SizedBox(height: context.u(6)),
          Text(
            right ? tr('Угадано за {0} с! +{1}', [steps[_step].round(), steps.length - _step]) : tr('Не угадано'),
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800, color: right ? context.accent : Colors.redAccent),
          ),
        ]),
      SizedBox(height: context.u(14)),
      // полоска секунд: 1 2 3 4 5 6
      Row(children: [
        for (var i = 0; i < steps.length; i++)
          Expanded(
            child: Container(
              height: context.u(8),
              margin: EdgeInsets.symmetric(horizontal: context.u(2)),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: i <= _step ? context.accent : Colors.white.withValues(alpha: 0.15),
              ),
            ),
          ),
      ]),
      SizedBox(height: context.u(4)),
      Row(children: [
        for (var i = 0; i < steps.length; i++)
          Expanded(
              child: Text(tr('{0} с', [steps[i].round()]),
                  textAlign: TextAlign.center, style: TextStyle(color: dim, fontSize: 11))),
      ]),
      SizedBox(height: context.u(12)),
      if (_loading)
        Center(child: CircularProgressIndicator(color: context.accent))
      else if (_failed)
        Column(children: [
          Text(tr('Этот трек не загрузился'), textAlign: TextAlign.center),
          TextButton(onPressed: _next, child: Text(tr('Следующий'))),
        ])
      else if (!_revealed)
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _listen,
              icon: const Icon(Icons.play_arrow_rounded, color: Colors.black),
              label: Text(tr('Слушать {0} с', [steps[_step].round()]), style: const TextStyle(color: Colors.black)),
            ),
          ),
          SizedBox(width: context.u(8)),
          OutlinedButton(
            onPressed: _skip,
            child: Text(_step + 1 < steps.length ? tr('+1 секунда') : tr('Сдаюсь')),
          ),
        ]),
      SizedBox(height: context.u(12)),
      for (final o in _options)
        Padding(
          padding: EdgeInsets.only(bottom: context.u(8)),
          child: Material(
            color: _revealed
                ? (o.id == t.id
                    ? context.accent.withValues(alpha: 0.35)
                    : o.id == _picked?.id
                        ? Colors.red.withValues(alpha: 0.3)
                        : Theme.of(context).cardColor)
                : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(context.r(16)),
            child: InkWell(
              borderRadius: BorderRadius.circular(context.r(16)),
              onTap: _loading || _failed ? null : () => _pick(o),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: context.u(16), vertical: context.u(14)),
                child: Text('${o.title} — ${o.artist}',
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ),
      if (_revealed)
        FilledButton(
          onPressed: _next,
          child: Text(_round + 1 < _order.length ? tr('Дальше') : tr('Итоги'),
              style: const TextStyle(color: Colors.black)),
        ),
    ]);
  }

  Widget _summary(BuildContext context) {
    final dim = Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6);
    final max = _order.length * steps.length;
    return ListView(padding: EdgeInsets.all(context.u(16)), children: [
      SizedBox(height: context.u(20)),
      Icon(Icons.emoji_events_rounded, size: context.u(80), color: context.accent),
      Text(tr('{0} из {1} очков', [_score, max]),
          textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
      Text(tr('Угадано песен: {0} из {1}', [_results.where((r) => r.$2 > 0).length, _order.length]),
          textAlign: TextAlign.center, style: TextStyle(color: dim)),
      SizedBox(height: context.u(16)),
      for (final r in _results)
        ListTile(
          leading: Cover(track: r.$1, size: context.u(44), radius: context.u(6)),
          title: Text(r.$1.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(r.$1.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Text(r.$2 > 0 ? '+${r.$2}' : '—',
              style: TextStyle(fontWeight: FontWeight.w800, color: r.$2 > 0 ? context.accent : dim)),
        ),
      SizedBox(height: context.u(12)),
      FilledButton(
        onPressed: () {
          _snip.stop();
          setState(() {
            _order = ([...widget.tracks]..shuffle(_rnd)).take(rounds).toList();
            _round = 0;
            _score = 0;
            _results.clear();
          });
          _newRound();
        },
        child: Text(tr('Ещё раз'), style: const TextStyle(color: Colors.black)),
      ),
    ]);
  }
}
