import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../glass.dart';
import '../services/importer.dart';
import '../services/store.dart';
import '../ui.dart';
import '../i18n.dart';

/// «Импорт с ПК»: файл «.echoesplaylist» из ECHOES на компьютере (или .m3u / .txt) → плейлисты на телефоне.
Future<void> importFromPc(BuildContext context) async {
  final go = await showGlassSheet<bool>(context, (ctx) {
    final dim = Theme.of(ctx).textTheme.bodySmall?.color?.withValues(alpha: 0.7);
    Widget step(String n, String text) => Padding(
          padding: EdgeInsets.only(bottom: ctx.u(10)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
              radius: ctx.u(12),
              backgroundColor: ctx.accent,
              child: Text(n, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 12)),
            ),
            SizedBox(width: ctx.u(10)),
            Expanded(child: Text(text, style: TextStyle(color: dim))),
          ]),
        );
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Плейлисты с компьютера'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      SizedBox(height: ctx.u(14)),
      step('1', tr('В ECHOES на ПК: «＋ Новый плейлист» → «Перенести все плейлисты на телефон…»')),
      step('2', tr('Отправьте файл себе: Telegram «Избранное», iCloud Drive или почта')),
      step('3', tr('На iPhone откройте файл → «Поделиться» → «Сохранить в Файлы»')),
      step('4', tr('Нажмите «Выбрать файл» и найдите его')),
      SizedBox(height: ctx.u(8)),
      SizedBox(
        width: double.infinity,
        height: ctx.u(50),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(shape: context.pill),
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.folder_open_rounded, color: Colors.black),
          label: Text(tr('Выбрать файл'), style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
        ),
      ),
    ]);
  });
  if (go != true || !context.mounted) return;

  final XFile? file;
  try {
    file = await openFile(acceptedTypeGroups: [
      XTypeGroup(
        label: tr('Плейлисты'),
        extensions: ['echoesplaylist', 'm3u', 'm3u8', 'txt', 'json'],
        uniformTypeIdentifiers: ['public.item'],
      ),
    ]);
  } catch (e) {
    if (context.mounted) _toast(context, tr('Не удалось открыть «Файлы»: {0}', [e]));
    return;
  }
  if (file == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final nav = Navigator.of(context, rootNavigator: true); // окно «Переношу…» — в корневом навигаторе
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          CircularProgressIndicator(color: ctx.accent),
          SizedBox(width: ctx.u(16)),
          Expanded(child: Text(tr('Переношу плейлисты…'))),
        ]),
      ),
    ),
  );
  String msg;
  try {
    final bytes = await file.readAsBytes();
    final name = file.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
    var lists = Importer.parse(utf8.decode(bytes, allowMalformed: true), fallbackName: name);
    lists = await Importer.resolve(lists);
    final total = lists.fold<int>(0, (s, l) => s + l.$2.length);
    final added = Store.instance.importPlaylists(lists);
    msg = tr('Готово: {0} {1}, {2} тр. {3}', [
      lists.length,
      _pl(lists.length),
      total,
      added < total ? tr('(новых — {0}, остальные уже были)', [added]) : ''
    ]);
  } on FormatException catch (e) {
    msg = tr('Не получилось прочитать файл: {0}', [e.message]);
  } catch (e) {
    msg = tr('Ошибка импорта: {0}', [e]);
  }
  nav.pop();
  messenger.showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 6)));
}

String _pl(int n) {
  final d = n % 10, h = n % 100;
  if (d == 1 && h != 11) return tr('плейлист');
  if (d >= 2 && d <= 4 && (h < 12 || h > 14)) return tr('плейлиста');
  return tr('плейлистов');
}

void _toast(BuildContext context, String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
