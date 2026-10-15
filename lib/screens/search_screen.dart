import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/audio.dart';
import '../services/sc.dart';
import '../services/store.dart';
import '../services/search.dart';
import '../services/ytm_artist.dart';
import '../ui.dart';
import '../widgets.dart';
import 'album_screen.dart';
import 'artist_screen.dart';
import '../i18n.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with AutomaticKeepAliveClientMixin {
  final _c = TextEditingController();
  final _focus = FocusNode();
  List<Track> _results = [];
  List<ScAlbum> _albums = [];
  List<YtmArtistRef> _artists = [];
  bool _busy = false;
  String? _err;
  int _token = 0;
  SearchSource _src = SearchSource.all; // «Все» = YouTube Music + SoundCloud
  String _last = '';
  // подсказки при вводе (как в Spotify): варианты запроса и сразу исполнители/песни
  Timer? _sugTimer;
  int _sugToken = 0;
  List<String> _sugQ = [];
  List<YtmSuggestion> _sugItems = [];

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _sugTimer?.cancel();
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onType(String v) {
    setState(() {});
    _sugTimer?.cancel();
    final q = v.trim();
    if (q.isEmpty) {
      setState(() {
        _sugQ = [];
        _sugItems = [];
      });
      return;
    }
    _sugTimer = Timer(const Duration(milliseconds: 220), () async {
      final my = ++_sugToken;
      try {
        final (qs, items) = await YtmBrowse.instance.suggest(q);
        if (!mounted || my != _sugToken) return;
        setState(() {
          _sugQ = qs.take(6).toList();
          _sugItems = items.take(5).toList();
        });
      } catch (_) {}
    });
  }

  bool get _showSuggest => _focus.hasFocus && _c.text.trim().isNotEmpty && (_sugQ.isNotEmpty || _sugItems.isNotEmpty);

  Widget _suggestions(BuildContext context) {
    final dim = Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6);
    final typed = _c.text.trim().toLowerCase();
    Widget bold(String s) {
      final i = s.toLowerCase().indexOf(typed);
      if (typed.isEmpty || i < 0) return Text(s, maxLines: 1, overflow: TextOverflow.ellipsis);
      return Text.rich(
        TextSpan(children: [
          TextSpan(text: s.substring(0, i), style: TextStyle(color: dim)),
          TextSpan(text: s.substring(i, i + typed.length), style: const TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: s.substring(i + typed.length), style: TextStyle(color: dim)),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return ListView(
      padding: EdgeInsets.only(bottom: context.u(200)),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        for (final it in _sugItems)
          ListTile(
            leading: it.kind == 'artist'
                ? CircleAvatar(
                    radius: context.u(24),
                    backgroundColor: Theme.of(context).cardColor,
                    backgroundImage: it.image != null ? NetworkImage(it.image!) : null,
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(context.u(6)),
                    child: it.image != null
                        ? Image.network(it.image!, width: context.u(48), height: context.u(48), fit: BoxFit.cover)
                        : SizedBox(width: context.u(48), height: context.u(48)),
                  ),
            title: Text(it.title,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(it.sub, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing:
                Icon(it.kind == 'song' ? Icons.play_circle_outline_rounded : Icons.chevron_right_rounded, color: dim),
            onTap: () {
              _focus.unfocus();
              if (it.kind == 'artist') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => ArtistScreen(name: it.title, ytm: it.id)));
              } else if (it.kind == 'album') {
                openAlbum(context,
                    ScAlbum(0, it.title, it.sub.split(' • ').last, null, it.image, 0, null, 'album', ytm: it.id));
              } else if (it.track != null) {
                audio.playList([it.track!], 0);
              }
            },
          ),
        for (final q in _sugQ)
          ListTile(
            leading: const Icon(Icons.search_rounded),
            title: bold(q),
            trailing: IconButton(
              tooltip: tr('Подставить'),
              icon: Icon(Icons.north_west_rounded, color: dim),
              onPressed: () {
                _c.text = '$q ';
                _c.selection = TextSelection.collapsed(offset: _c.text.length);
                _onType(_c.text);
              },
            ),
            onTap: () {
              _c.text = q;
              _search(q);
            },
          ),
      ],
    );
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _search(String q) async {
    q = q.trim();
    if (q.isEmpty) return;
    _focus.unfocus();
    Store.instance.addSearch(q);
    _last = q;
    final my = ++_token;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      // альбомы и исполнители — официальные, с YouTube Music (параллельно с треками; их ошибка не мешает)
      final albumsF = YtmBrowse.instance.searchAlbums(q).catchError((_) => <ScAlbum>[]);
      final artistsF = YtmBrowse.instance.searchArtists(q).catchError((_) => <YtmArtistRef>[]);
      final r = await SearchService.search(q, _src);
      final al = await albumsF;
      final ar = await artistsF;
      if (my != _token) return;
      setState(() {
        _results = r;
        _albums = al;
        _artists = ar;
      });
      if (r.isEmpty && al.isEmpty && ar.isEmpty) _err = tr('Ничего не нашлось');
    } catch (e) {
      if (my == _token) _err = tr('Нет соединения или поиск недоступен');
    } finally {
      if (my == _token && mounted) setState(() => _busy = false);
    }
  }

  /// Верх списка результатов: исполнители, альбомы, заголовок «Треки».
  List<Widget> _headWidgets() => [
        if (_artists.isNotEmpty) ...[SectionTitle(tr('Исполнители')), _ArtistRow(artists: _artists)],
        if (_albums.isNotEmpty) ...[SectionTitle(tr('Альбомы')), AlbumRow(albums: _albums, showArtist: true)],
        if (_results.isNotEmpty && (_albums.isNotEmpty || _artists.isNotEmpty)) SectionTitle(tr('Треки')),
      ];

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final st = Store.instance;
    return SafeArea(
      bottom: false,
      child: Column(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(context.u(16), context.u(12), context.u(16), context.u(6)),
          child: TextField(
            controller: _c,
            focusNode: _focus,
            textInputAction: TextInputAction.search,
            onSubmitted: _search,
            decoration: InputDecoration(
              hintText: tr('Песня, исполнитель или альбом'),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _c.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() {
                        _c.clear();
                        _results = [];
                        _albums = [];
                        _artists = [];
                        _err = null;
                      }),
                    ),
              filled: true,
              fillColor: Theme.of(context).cardColor,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(context.r(28)), borderSide: BorderSide.none),
              contentPadding: EdgeInsets.symmetric(vertical: context.u(12)),
            ),
            onChanged: _onType,
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(context.u(16), 0, context.u(16), context.u(4)),
          child: Wrap(runSpacing: context.u(6), children: [
            for (final s in [
              (SearchSource.all, tr('Все')),
              (SearchSource.ytm, 'YouTube Music'),
              (SearchSource.yt, 'YouTube'),
              (SearchSource.sc, 'SoundCloud'),
            ])
              Padding(
                padding: EdgeInsets.only(right: context.u(8)),
                child: ChoiceChip(
                  label: Text(s.$2),
                  selected: _src == s.$1,
                  onSelected: (_) {
                    setState(() => _src = s.$1);
                    if (_last.isNotEmpty) _search(_last);
                  },
                ),
              ),
          ]),
        ),
        if (_busy) LinearProgressIndicator(minHeight: 2, color: context.accent, backgroundColor: Colors.transparent),
        Expanded(
          child: _showSuggest
              ? _suggestions(context)
              : _results.isNotEmpty || _albums.isNotEmpty || _artists.isNotEmpty
                  ? ListView.builder(
                      padding: EdgeInsets.only(bottom: context.u(200)),
                      itemCount: _headWidgets().length + _results.length,
                      itemBuilder: (context, i) {
                        final head = _headWidgets();
                        if (i < head.length) return head[i];
                        final j = i - head.length;
                        return TrackTile(track: _results[j], onTap: () => audio.playList(_results, j));
                      },
                    )
                  : ListenableBuilder(
                      listenable: st,
                      builder: (context, _) => ListView(children: [
                        if (_err != null)
                          Padding(
                            padding: EdgeInsets.all(context.u(24)),
                            child: Text(_err!, textAlign: TextAlign.center),
                          ),
                        if (st.searches.isNotEmpty)
                          SectionTitle(tr('Вы искали'),
                              trailing: TextButton(onPressed: st.clearSearches, child: Text(tr('Очистить')))),
                        for (final q in st.searches)
                          ListTile(
                            leading: const Icon(Icons.history_rounded),
                            title: Text(q),
                            onTap: () {
                              _c.text = q;
                              _search(q);
                            },
                          ),
                        if (st.searches.isEmpty && _err == null)
                          Padding(
                            padding: EdgeInsets.all(context.u(32)),
                            child: Column(children: [
                              Icon(Icons.graphic_eq_rounded, size: context.u(64), color: context.accent),
                              SizedBox(height: context.u(12)),
                              Text(tr('Найдите любую песню — она заиграет сразу,\nбез скачивания на телефон'),
                                  textAlign: TextAlign.center),
                            ]),
                          ),
                      ]),
                    ),
        ),
      ]),
    );
  }
}

/// Лента исполнителей в поиске: круглое фото, имя, «… слушателей в месяц»; нажатие — страница исполнителя.
class _ArtistRow extends StatelessWidget {
  final List<YtmArtistRef> artists;
  const _ArtistRow({required this.artists});

  @override
  Widget build(BuildContext context) {
    final s = context.u(92);
    final dim = Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6);
    return SizedBox(
      height: s + context.u(10) + MediaQuery.textScalerOf(context).scale(36),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: context.u(16)),
        itemCount: artists.length,
        separatorBuilder: (_, __) => SizedBox(width: context.u(14)),
        itemBuilder: (context, i) {
          final a = artists[i];
          return GestureDetector(
            onTap: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => ArtistScreen(name: a.name, ytm: a.id))),
            child: SizedBox(
              width: s,
              child: Column(children: [
                CircleAvatar(
                  radius: s / 2,
                  backgroundColor: Theme.of(context).cardColor,
                  backgroundImage: a.image != null ? NetworkImage(a.image!) : null,
                  child: a.image == null ? Icon(Icons.person_rounded, size: s * 0.45) : null,
                ),
                SizedBox(height: context.u(6)),
                Text(a.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(a.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: dim)),
              ]),
            ),
          );
        },
      ),
    );
  }
}
