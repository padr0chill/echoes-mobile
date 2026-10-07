import 'package:flutter/material.dart';

import '../models.dart';
import '../services/audio.dart';
import '../services/sc.dart';
import '../services/store.dart';
import '../services/wave.dart';
import '../ui.dart';
import '../widgets.dart';

class _Section {
  final String title;
  final List<Track> tracks;
  const _Section(this.title, this.tracks);
}

/// «Для вас»: подборки по вашей истории и лайкам — «Похоже на …», «Ещё от …», популярное.
class ForYouScreen extends StatefulWidget {
  const ForYouScreen({super.key});

  @override
  State<ForYouScreen> createState() => _ForYouScreenState();
}

class _ForYouScreenState extends State<ForYouScreen> with AutomaticKeepAliveClientMixin {
  Future<List<_Section>>? _f;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _f = _load();
  }

  Future<List<_Section>> _load() async {
    final st = Store.instance;
    final sc = ScService.instance;
    final out = <_Section>[];
    final seeds = <Track>{...st.history.take(3), ...st.liked.take(2)}.toList();
    for (final s in seeds.take(3)) {
      try {
        final r = await Wave.instance.relatedFor(s);
        if (r.length >= 4) out.add(_Section('Похоже на «${s.title}»', r.take(15).toList()));
      } catch (_) {}
    }
    final artists = st.topArtists(3);
    for (final a in artists) {
      try {
        final r = await sc.searchTracks(a, limit: 20);
        if (r.length >= 3) out.add(_Section('Ещё от $a', r.take(15).toList()));
      } catch (_) {}
    }
    if (out.length < 3) {
      for (final q in const [('Популярное сейчас', 'top hits 2026'), ('Новый русский рэп', 'новый русский рэп 2026')]) {
        try {
          final r = await sc.searchTracks(q.$2, limit: 20);
          if (r.isNotEmpty) out.add(_Section(q.$1, r.take(15).toList()));
        } catch (_) {}
      }
    }
    if (out.isEmpty) throw Exception('нет сети');
    return out;
  }

  Future<void> _refresh() async {
    final f = _load();
    setState(() => _f = f);
    await f.catchError((_) => <_Section>[]);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: context.accent,
        onRefresh: _refresh,
        child: FutureBuilder<List<_Section>>(
          future: _f,
          builder: (context, snap) {
            final head = Padding(
              padding: EdgeInsets.fromLTRB(context.u(16), context.u(16), context.u(16), 0),
              child: const Text('Для вас', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
            );
            if (snap.connectionState != ConnectionState.done) {
              return ListView(children: [
                head,
                SizedBox(height: context.u(80)),
                Center(child: CircularProgressIndicator(color: context.accent)),
              ]);
            }
            if (snap.hasError || (snap.data ?? []).isEmpty) {
              return ListView(children: [
                head,
                Padding(
                  padding: EdgeInsets.all(context.u(24)),
                  child: const Text('Не получилось собрать подборки — проверьте интернет и потяните вниз',
                      textAlign: TextAlign.center),
                ),
              ]);
            }
            return ListView(
              padding: EdgeInsets.only(bottom: context.u(130)),
              children: [
                head,
                for (final s in snap.data!) ...[
                  SectionTitle(s.title),
                  SizedBox(
                    height: context.u(196),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.symmetric(horizontal: context.u(16)),
                      itemCount: s.tracks.length,
                      separatorBuilder: (_, __) => SizedBox(width: context.u(12)),
                      itemBuilder: (context, i) => _Card(track: s.tracks[i], onTap: () => audio.playList(s.tracks, i)),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;
  const _Card({required this.track, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final w = context.u(140);
    return GestureDetector(
      onTap: onTap,
      onLongPress: () => showTrackMenu(context, track),
      child: SizedBox(
        width: w,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Cover(track: track, size: w, radius: context.u(12)),
          SizedBox(height: context.u(6)),
          Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6))),
        ]),
      ),
    );
  }
}
