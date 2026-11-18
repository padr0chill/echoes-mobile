import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n.dart';
import '../models.dart';
import '../services/audio.dart';
import '../services/echoes_net.dart';
import '../services/net_protocol.dart';
import '../services/store.dart';
import '../skins/phantom.dart';
import '../ui.dart';
import '../widgets.dart';

class NetScreen extends StatefulWidget {
  const NetScreen({super.key, this.net = const EchoesNet()});
  final EchoesNet net;

  @override
  State<NetScreen> createState() => _NetScreenState();
}

class _NetScreenState extends State<NetScreen> {
  NetIdentity? _account;
  bool _accountBusy = true, _sending = false;
  List<NetNote> _notes = [];
  Map<String, String> _names = {};
  bool _loadingFeed = true, _feedUnavailable = false;
  Future<NetProfile?>? _profile;
  int _feedRequest = 0;

  EchoesNet get _net => widget.net;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAccount());
    unawaited(_refreshFeed());
  }

  Future<void> _loadAccount() async {
    try {
      final account = await _net.loadIdentity();
      if (mounted) _setAccount(account);
    } catch (_) {
      if (mounted) _notice(context, tr('Не удалось открыть ключ ECHOES.NET'));
    } finally {
      if (mounted) setState(() => _accountBusy = false);
    }
  }

  void _setAccount(NetIdentity? account) {
    setState(() {
      _account = account;
      _profile = account == null
          ? null
          : _net.profile(account.pubkey, onion: account.onion);
      _profile
          ?.ignore(); // The profile tab may be opened after the request completes.
    });
  }

  Future<void> _refreshFeed() async {
    final request = ++_feedRequest;
    setState(() => _loadingFeed = true);
    try {
      final notes = await _net.feed(me: _account?.pubkey);
      if (!mounted || request != _feedRequest) return;
      setState(() {
        _notes = notes;
        _feedUnavailable = false;
        _loadingFeed = false;
      });
      final names = await _net.authorNames(notes.map((note) => note.author));
      if (mounted && request == _feedRequest) {
        setState(() => _names = {..._names, ...names});
      }
    } catch (_) {
      if (mounted && request == _feedRequest && _loadingFeed) {
        setState(() {
          _feedUnavailable = true;
          _loadingFeed = false;
        });
      }
    }
  }

  Future<void> _signIn() async {
    if (_accountBusy) return;
    final key = await showDialog<String>(
      context: context,
      builder: (_) => const _KeyDialog(),
    );
    if (!mounted || key == null) return;
    setState(() => _accountBusy = true);
    try {
      final account = await _net.signIn(key);
      if (mounted) _setAccount(account);
    } on FormatException {
      if (mounted) {
        _notice(
          context,
          tr('Не удалось прочитать ключ. Проверьте файл identity.key.'),
        );
      }
    } catch (_) {
      if (mounted) _notice(context, tr('Не удалось сохранить ключ ECHOES.NET'));
    } finally {
      if (mounted) setState(() => _accountBusy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _accountBusy = true);
    try {
      await _net.signOut();
      if (mounted) _setAccount(null);
    } catch (_) {
      if (mounted) _notice(context, tr('Не удалось удалить ключ ECHOES.NET'));
    } finally {
      if (mounted) setState(() => _accountBusy = false);
    }
  }

  Future<void> _compose() async {
    final account = _account;
    if (account == null || _sending) return;
    final draft = await _writeNote(context, track: audio.current);
    if (!mounted || draft == null) return;
    setState(() => _sending = true);
    try {
      await _net.post(account, draft.$1, draft.$2);
      if (mounted) {
        _notice(context, tr('Пост опубликован'));
        unawaited(_refreshFeed());
      }
    } catch (_) {
      if (mounted) _notice(context, tr('Ни один релей не подтвердил отправку'));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _openProfile(NetNote note) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(tr('Профиль ECHOES.NET'))),
        body: _NetProfileView(profile: _net.profile(note.author)),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final tabs = TabBar(
      dividerHeight: context.phantom ? 0 : null,
      indicatorSize: context.phantom ? TabBarIndicatorSize.tab : null,
      indicator: context.phantom
          ? BoxDecoration(
              color: const Color(0xFF333333),
              borderRadius: BorderRadius.circular(32),
            )
          : null,
      tabs: [
        Tab(text: tr('Лента')),
        Tab(text: tr('Профиль')),
      ],
    );
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ECHOES.NET'),
          bottom: context.phantom
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(60),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
                    child: PhantomPanel(radius: 32, solid: true, child: tabs),
                  ),
                )
              : tabs,
        ),
        body: TabBarView(
          children: [
            RefreshIndicator(
              onRefresh: _refreshFeed,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
                children: [
                  if (_account != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _sending ? null : _compose,
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(tr(_sending ? 'Отправка…' : 'Новый пост')),
                      ),
                    ),
                  if (_loadingFeed) const LinearProgressIndicator(),
                  if (_feedUnavailable)
                    ListTile(
                      title: Text(tr('Релеи ECHOES.NET недоступны')),
                      trailing: IconButton(
                        tooltip: tr('Повторить'),
                        onPressed: _refreshFeed,
                        icon: const Icon(Icons.refresh),
                      ),
                    ),
                  if (!_loadingFeed && !_feedUnavailable && _notes.isEmpty)
                    ListTile(
                      title: Text(tr('В публичной ленте пока нет постов')),
                    ),
                  for (final note in _notes)
                    _NoteCard(
                      note: note,
                      name: _names[note.author],
                      onAuthor: () => _openProfile(note),
                      onThread: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => _ThreadScreen(
                            net: _net,
                            note: note,
                            authorName: _names[note.author],
                            account: _account,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_accountBusy)
              const Center(child: CircularProgressIndicator())
            else if (_account case final account?)
              _NetProfileView(
                profile: _profile!,
                header: [
                  ListTile(
                    title: Text(tr('Ваш код ECHOES.NET')),
                    subtitle: SelectableText(account.onion),
                    trailing: IconButton(
                      tooltip: tr('Копировать код'),
                      icon: const Icon(Icons.copy_outlined),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: account.onion),
                        );
                        if (context.mounted) {
                          _notice(context, tr('Код скопирован'));
                        }
                      },
                    ),
                  ),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => _setAccount(account),
                        child: Text(tr('Обновить профиль')),
                      ),
                      TextButton(onPressed: _signOut, child: Text(tr('Выйти'))),
                    ],
                  ),
                ],
              )
            else
              ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    tr(
                      'Войдите, чтобы открыть профиль с ПК и писать в ECHOES.NET.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _signIn,
                    icon: const Icon(Icons.key_outlined),
                    label: Text(tr('Войти с ключом ПК')),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _KeyDialog extends StatefulWidget {
  const _KeyDialog();

  @override
  State<_KeyDialog> createState() => _KeyDialogState();
}

class _KeyDialogState extends State<_KeyDialog> {
  String _key = '';
  bool _picking = false;
  String? _error;

  Future<void> _pickKey() async {
    setState(() => _picking = true);
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'ECHOES.NET',
            extensions: ['key'],
            uniformTypeIdentifiers: ['public.data'],
            mimeTypes: ['*/*'],
          ),
        ],
      );
      if (file == null || !mounted) return;
      if (await file.length() > 2048) throw const FormatException();
      final raw = await file.readAsString();
      NetIdentity.parseSeed(raw);
      if (mounted) Navigator.pop(context, raw);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = tr(
            'Не удалось прочитать ключ. Проверьте файл identity.key.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _submit() {
    try {
      NetIdentity.parseSeed(_key);
      Navigator.pop(context, _key);
    } on FormatException {
      setState(
        () => _error = tr(
          'Не удалось прочитать ключ. Проверьте файл identity.key.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr('Войти с ключом ПК')),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(
              'На ПК откройте %USERPROFILE%\\Echoes\\net. Перенесите identity.key на iPhone или вставьте значение seed из файла. Храните ключ в секрете.',
            ),
          ),
          TextButton.icon(
            onPressed: _picking ? null : _pickKey,
            icon: const Icon(Icons.file_open_outlined),
            label: Text(tr('Выбрать identity.key')),
          ),
          TextField(
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            inputFormatters: [LengthLimitingTextInputFormatter(2048)],
            decoration: const InputDecoration(labelText: 'seed'),
            onChanged: (key) => setState(() {
              _key = key;
              _error = null;
            }),
            onSubmitted: (_) {
              if (_key.trim().isNotEmpty && !_picking) _submit();
            },
          ),
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr('Отмена')),
      ),
      FilledButton(
        onPressed: _key.trim().isEmpty || _picking ? null : _submit,
        child: Text(tr('Войти')),
      ),
    ],
  );
}

class _NetProfileView extends StatelessWidget {
  const _NetProfileView({required this.profile, this.header = const []});
  final Future<NetProfile?> profile;
  final List<Widget> header;

  @override
  Widget build(BuildContext context) => FutureBuilder<NetProfile?>(
    future: profile,
    builder: (context, snapshot) {
      final data = snapshot.data;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...header,
          if (snapshot.connectionState != ConnectionState.done)
            const LinearProgressIndicator()
          else if (snapshot.hasError)
            ListTile(title: Text(tr('Релеи ECHOES.NET недоступны')))
          else if (data == null)
            ListTile(title: Text(tr('Публичный профиль пока не найден')))
          else ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(
                data.name.isEmpty ? tr('Профиль ECHOES.NET') : data.name,
              ),
              subtitle: data.status.isEmpty ? null : Text(data.status),
            ),
            if (data.about.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(data.about),
              ),
            for (final list in data.playlists)
              Card(
                child: ListTile(
                  title: Text(list.name),
                  subtitle: Text(
                    list.description.isEmpty
                        ? tr('{0} треков', [list.tracks.length])
                        : list.description,
                  ),
                  leading: IconButton(
                    tooltip: tr('Слушать'),
                    onPressed: () => audio.playList(list.tracks, 0),
                    icon: const Icon(Icons.play_arrow),
                  ),
                  trailing: IconButton(
                    tooltip: tr('Добавить в «Мою музыку»'),
                    icon: const Icon(Icons.playlist_add),
                    onPressed: () {
                      final count = Store.instance.importPlaylists([
                        (list.name, list.tracks),
                      ]);
                      _notice(
                        context,
                        tr(
                          count == 0
                              ? 'Плейлист уже в медиатеке'
                              : 'Плейлист добавлен',
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ],
      );
    },
  );
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    this.name,
    this.onAuthor,
    this.onThread,
  });
  final NetNote note;
  final String? name;
  final VoidCallback? onAuthor, onThread;

  @override
  Widget build(BuildContext context) {
    final date = MaterialLocalizations.of(context).formatShortDate(note.date);
    final artist = name == null || name!.isEmpty ? note.shortAuthor : name!;
    return Card(
      margin: context.phantom ? const EdgeInsets.only(bottom: 9) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: context.phantom
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox.square(
                      dimension: 36,
                      child: PhantomArtworkPlaceholder(size: 36, title: name),
                    ),
                  )
                : const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text(artist),
            subtitle: Text(date),
            onTap: onAuthor,
          ),
          if (note.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(note.text),
            ),
          if (note.track case final track?)
            ListTile(
              leading: context.phantom
                  ? Cover(track: track, size: 38, radius: 7)
                  : const Icon(Icons.play_circle_outline),
              title: Text(track.title),
              subtitle: Text(track.artist),
              onTap: () => audio.playList([track], 0),
              trailing: IconButton(
                tooltip: tr('В конец очереди'),
                onPressed: () => audio.addToQueue(track),
                icon: const Icon(Icons.queue_music),
              ),
            ),
          if (onThread != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextButton.icon(
                onPressed: onThread,
                icon: const Icon(Icons.chat_bubble_outline),
                label: Text(tr('Обсуждение')),
              ),
            ),
        ],
      ),
    );
  }
}

class _ThreadScreen extends StatefulWidget {
  const _ThreadScreen({
    required this.net,
    required this.note,
    required this.account,
    this.authorName,
  });
  final EchoesNet net;
  final NetNote note;
  final NetIdentity? account;
  final String? authorName;

  @override
  State<_ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<_ThreadScreen> {
  List<NetNote> _replies = [];
  Set<String> _likes = {};
  bool _loading = true, _offline = false, _sending = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final thread = await widget.net.thread(widget.note);
      if (mounted) {
        setState(() {
          _replies = thread.replies;
          _likes = {..._likes, ...thread.likes};
          _offline = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _offline = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send({required bool like}) async {
    final account = widget.account;
    if (account == null || _sending) return;
    final draft = like ? null : await _writeNote(context, reply: true);
    if (!mounted || (!like && draft == null)) return;
    setState(() => _sending = true);
    try {
      if (like) {
        await widget.net.like(account, widget.note);
        if (mounted) setState(() => _likes.add(account.pubkey));
      } else {
        await widget.net.reply(account, widget.note, draft!.$1);
        if (mounted) _notice(context, tr('Ответ отправлен'));
      }
      if (mounted) await _refresh();
    } catch (_) {
      if (mounted) _notice(context, tr('Ни один релей не подтвердил отправку'));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final liked = _likes.contains(widget.account?.pubkey);
    final canSend = widget.account != null && !_sending;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Обсуждение'))),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: [
            _NoteCard(note: widget.note, name: widget.authorName),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: canSend && !liked ? () => _send(like: true) : null,
                  icon: Icon(liked ? Icons.favorite : Icons.favorite_outline),
                  label: Text('${_likes.length}'),
                ),
                if (widget.account != null)
                  TextButton.icon(
                    onPressed: canSend ? () => _send(like: false) : null,
                    icon: const Icon(Icons.reply),
                    label: Text(tr('Ответить')),
                  ),
              ],
            ),
            if (_loading || _sending) const LinearProgressIndicator(),
            if (_offline)
              ListTile(
                title: Text(tr('Релеи ECHOES.NET недоступны')),
                trailing: IconButton(
                  tooltip: tr('Повторить'),
                  icon: const Icon(Icons.refresh),
                  onPressed: _refresh,
                ),
              ),
            for (final note in _replies) _NoteCard(note: note),
          ],
        ),
      ),
    );
  }
}

Future<(String, Track?)?> _writeNote(
  BuildContext context, {
  Track? track,
  bool reply = false,
}) {
  var text = '';
  var attach = false;
  return showDialog<(String, Track?)>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          title: Text(tr(reply ? 'Ответить' : 'Новый пост')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  autofocus: true,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 3400,
                  decoration: InputDecoration(hintText: tr('Текст сообщения')),
                  onChanged: (value) => setState(() => text = value),
                ),
                if (track != null)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('Прикрепить текущий трек')),
                    subtitle: Text(track.title),
                    value: attach,
                    onChanged: (value) =>
                        setState(() => attach = value ?? false),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('Отмена')),
            ),
            FilledButton(
              onPressed: text.trim().isEmpty && !attach
                  ? null
                  : () => Navigator.pop(context, (
                      text.trim(),
                      attach ? track : null,
                    )),
              child: Text(tr(reply ? 'Отправить' : 'Опубликовать')),
            ),
          ],
        );
      },
    ),
  );
}

void _notice(BuildContext context, String message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message)));
