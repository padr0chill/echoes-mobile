import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../glass.dart';
import '../models.dart';
import '../services/audio.dart';
import '../services/lyrics.dart';
import '../ui.dart';

/// «Найти другой текст»: свой запрос и список найденных вариантов (синхронные помечены).
/// Выбранный — сохраняется для трека. → выбранный текст или null.
Future<Lyrics?> pickLyrics(BuildContext context, Track t) {
  final (a, ti) = LyricsService.cleanup(t.artist, t.title);
  final ctl = TextEditingController(text: '$a $ti');
  Future<List<LyricsCandidate>> run([String? q]) => LyricsService.instance.search(t, query: q);
  var future = run();
  return showGlassSheet<Lyrics>(
    context,
    (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final dim = Theme.of(ctx).textTheme.bodySmall?.color?.withValues(alpha: 0.6);
      return SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.75,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(ctx.u(16), ctx.u(16), ctx.u(16), ctx.u(8)),
            child: const Text('Найти текст', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: ctx.u(16)),
            child: TextField(
              controller: ctl,
              textInputAction: TextInputAction.search,
              onSubmitted: (q) => setS(() => future = run(q)),
              decoration: InputDecoration(
                hintText: 'Исполнитель и название',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward_rounded),
                  onPressed: () => setS(() => future = run(ctl.text)),
                ),
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(ctx.r(14)), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<LyricsCandidate>>(
              future: future,
              builder: (ctx, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return Center(child: CircularProgressIndicator(color: ctx.accent));
                }
                final list = snap.data ?? const <LyricsCandidate>[];
                if (list.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: EdgeInsets.all(ctx.u(24)),
                      child: Text('Ничего не нашлось — попробуйте другой запрос или «Свой текст»',
                          textAlign: TextAlign.center, style: TextStyle(color: dim)),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (ctx, i) {
                    final c = list[i];
                    final ly = c.toLyrics();
                    final first = ly?.lines
                        .firstWhere((l) => l.text.trim().isNotEmpty, orElse: () => const LyricLine(Duration.zero, ''));
                    return ListTile(
                      title: Text('${c.artist} — ${c.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        [
                          if (c.seconds > 0) fmtDuration(Duration(seconds: c.seconds)),
                          c.source,
                          if (first != null && first.text.isNotEmpty) '«${first.text}…»',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: c.hasSynced ? ctx.accent.withValues(alpha: 0.2) : Colors.white10,
                          borderRadius: BorderRadius.circular(ctx.r(8)),
                        ),
                        child: Text(c.hasSynced ? 'синхр.' : 'текст',
                            style: TextStyle(fontSize: 12, color: c.hasSynced ? ctx.accent : dim)),
                      ),
                      onTap: ly == null
                          ? null
                          : () async {
                              await LyricsService.instance.save(t, ly);
                              if (ctx.mounted) Navigator.pop(ctx, ly);
                            },
                    );
                  },
                );
              },
            ),
          ),
        ]),
      );
    }),
  );
}

/// «Свой текст»: вставить текст песни (из заметок, сайта и т. п.) → обычный текст (без таймингов).
Future<Lyrics?> ownLyrics(BuildContext context, Track t) async {
  final ctl = TextEditingController();
  final paste = await Clipboard.getData('text/plain');
  if ((paste?.text ?? '').split('\n').length >= 4) ctl.text = paste!.text!;
  if (!context.mounted) return null;
  final txt = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Свой текст'),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: ctl,
          maxLines: 12,
          minLines: 6,
          decoration: const InputDecoration(hintText: 'Вставьте текст песни — по строке на строку'),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Сохранить')),
      ],
    ),
  );
  if (txt == null || txt.trim().isEmpty) return null;
  final ly = Lyrics(
      [for (final s in txt.replaceAll('\r', '').split('\n')) LyricLine(Duration.zero, s.trimRight())], false,
      source: 'свой');
  await LyricsService.instance.save(t, ly);
  return ly;
}

/// Синхронизация «по нажатию», как в караоке-редакторах: трек играет, вы нажимаете «Строка», когда
/// начинается очередная строка. «Назад» — отменить последнюю отметку, «Авто» — разложить остаток
/// примерно. Готово — тайминги сохраняются для трека.
class LyricsSyncScreen extends StatefulWidget {
  final Track track;
  final List<String> lines;
  const LyricsSyncScreen({super.key, required this.track, required this.lines});

  @override
  State<LyricsSyncScreen> createState() => _LyricsSyncScreenState();
}

class _LyricsSyncScreenState extends State<LyricsSyncScreen> {
  late final List<String> _lines = widget.lines.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  final _times = <Duration>[];
  final _sc = ScrollController();

  int get _cur => _times.length;

  @override
  void initState() {
    super.initState();
    // с начала песни
    audio.seek(Duration.zero);
    audio.play();
  }

  void _mark() {
    if (_cur >= _lines.length) return;
    HapticFeedback.lightImpact();
    setState(() => _times.add(audio.player.position));
    _follow();
  }

  void _undo() {
    if (_times.isEmpty) return;
    final back = _times.removeLast();
    audio.seek(back - const Duration(seconds: 2) < Duration.zero ? Duration.zero : back - const Duration(seconds: 2));
    setState(() {});
    _follow();
  }

  void _follow() {
    if (!_sc.hasClients) return;
    _sc.animateTo((_cur * 52.0 - 120).clamp(0, _sc.position.maxScrollExtent),
        duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
  }

  Future<void> _finish({bool autoRest = false}) async {
    final total = audio.player.duration ?? widget.track.duration;
    final lines = <LyricLine>[for (var i = 0; i < _times.length; i++) LyricLine(_times[i], _lines[i])];
    if (_cur < _lines.length) {
      if (!autoRest && _times.isNotEmpty) {
        // не дошли до конца — оставшиеся строки примерно, после последней отметки
        autoRest = true;
      }
      final from = _times.isEmpty ? Duration.zero : _times.last + const Duration(seconds: 2);
      final rest = LyricsService.autoSync(_lines.sublist(_cur), total - from);
      lines.addAll(rest.lines.map((l) => LyricLine(l.at + from, l.text)));
    }
    final ly = Lyrics(lines, true, source: 'синхронизировано вручную', approx: autoRest && _cur < _lines.length);
    await LyricsService.instance.save(widget.track, ly);
    if (mounted) Navigator.pop(context, ly);
  }

  @override
  Widget build(BuildContext context) {
    final dim = Colors.white.withValues(alpha: 0.45);
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E12),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Синхронизация текста'),
        actions: [TextButton(onPressed: _finish, child: const Text('Готово'))],
      ),
      body: Column(children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: context.u(16)),
          child: Text('Нажимайте «Строка», когда начинается выделенная строка',
              textAlign: TextAlign.center, style: TextStyle(color: dim)),
        ),
        StreamBuilder<Duration>(
          stream: audio.player.positionStream,
          builder: (context, s) => Padding(
            padding: EdgeInsets.all(context.u(6)),
            child: Text(fmtDuration(s.data ?? Duration.zero),
                style: TextStyle(color: context.accent, fontSize: 18, fontWeight: FontWeight.w800)),
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _sc,
            itemExtent: 52,
            padding: EdgeInsets.symmetric(horizontal: context.u(16), vertical: context.u(40)),
            itemCount: _lines.length,
            itemBuilder: (context, i) {
              final done = i < _cur, now = i == _cur;
              return Row(children: [
                SizedBox(
                  width: context.u(52),
                  child: Text(done ? fmtDuration(_times[i]) : '',
                      style: TextStyle(color: dim, fontSize: 12, fontFeatures: const [FontFeature.tabularFigures()])),
                ),
                Expanded(
                  child: Text(_lines[i],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: now ? 20 : 16,
                        fontWeight: now ? FontWeight.w900 : FontWeight.w600,
                        color: now ? Colors.white : (done ? dim : Colors.white70),
                      )),
                ),
              ]);
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.all(context.u(16)),
            child: Row(children: [
              IconButton.filledTonal(
                  tooltip: 'Отменить последнюю', onPressed: _undo, icon: const Icon(Icons.undo_rounded)),
              SizedBox(width: context.u(10)),
              Expanded(
                child: SizedBox(
                  height: context.u(64),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(shape: context.pill),
                    onPressed: _cur < _lines.length ? _mark : _finish,
                    icon:
                        Icon(_cur < _lines.length ? Icons.touch_app_rounded : Icons.check_rounded, color: Colors.black),
                    label: Text(_cur < _lines.length ? 'Строка ${_cur + 1}/${_lines.length}' : 'Готово',
                        style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
              SizedBox(width: context.u(10)),
              IconButton.filledTonal(
                tooltip: 'Остальное — автоматически',
                onPressed: () => _finish(autoRest: true),
                icon: const Icon(Icons.auto_fix_high_rounded),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
