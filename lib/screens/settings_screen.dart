import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';

import '../glass.dart';
import 'equalizer_screen.dart';
import '../services/offline.dart';
import '../services/store.dart';
import '../ui.dart';
import '../widgets.dart';

/// Настройки — по минимуму: цвет акцента, светлая тема, экономия трафика.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = Store.instance;
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: st,
        builder: (context, _) => ListView(
          padding: EdgeInsets.only(bottom: context.u(200)),
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(context.u(16), context.u(16), context.u(16), 0),
              child: ScreenTitle('Настройки'),
            ),
            const SectionTitle('Оформление'),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: context.u(16)),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'glass', icon: Icon(Icons.blur_on_rounded), label: Text('Обычная')),
                  ButtonSegment(value: 'winamp', icon: Icon(Icons.graphic_eq_rounded), label: Text('Эховамп')),
                ],
                selected: {st.skin},
                onSelectionChanged: (s) => st.setSkin(s.first),
                showSelectedIcon: false,
              ),
            ),
            if (st.winamp)
              Padding(
                padding: EdgeInsets.fromLTRB(context.u(16), context.u(8), context.u(16), 0),
                child: Text(
                    'Эховамп — весь интерфейс как Winamp 2 на ПК: ЖК-дисплей, спектр, MilkDrop, плейлисты. Без размытий — самая лёгкая тема.',
                    style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6))),
              ),
            if (!st.winamp) ...[
              SwitchListTile(
                secondary: const Icon(Icons.album_rounded),
                title: const Text('Винил вместо обложки'),
                subtitle: const Text('В плеере крутится пластинка, под ней — строка текста песни'),
                value: st.vinyl,
                onChanged: st.setVinyl,
              ),
              ListTile(
                leading: const Icon(Icons.wallpaper_rounded),
                title: const Text('Своё фото на фон'),
                subtitle: Text(st.bgPath == null ? 'Сейчас — размытая обложка трека' : 'Выбрано своё фото'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (st.bgPath != null)
                    IconButton(
                      tooltip: 'Убрать фото',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => _clearBackground(st),
                    ),
                  FilledButton.tonal(onPressed: () => _pickBackground(context), child: const Text('Выбрать')),
                ]),
              ),
              if (st.bgPath != null)
                SwitchListTile(
                  secondary: const Icon(Icons.blur_linear_rounded),
                  title: const Text('Размыть фото'),
                  value: st.bgBlur,
                  onChanged: st.setBgBlur,
                ),
            ],
            const SectionTitle('Цвет'),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: context.u(16)),
              child: Wrap(spacing: context.u(12), runSpacing: context.u(12), children: [
                for (var i = 0; i < Store.accents.length; i++)
                  GestureDetector(
                    onTap: () => st.setAccent(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: context.u(44),
                      height: context.u(44),
                      decoration: BoxDecoration(
                        color: Store.accents[i],
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: i == st.accentIndex ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
            SizedBox(height: context.u(8)),
            SwitchListTile(
              title: const Text('Светлая тема'),
              value: st.light,
              onChanged: st.setLight,
            ),
            const SectionTitle('Звук'),
            ListTile(
              leading: const Icon(Icons.equalizer_rounded),
              title: const Text('Эквалайзер'),
              subtitle: Text(st.eqEnabled ? 'Вкл · ${st.eqPreset}' : 'Выключен'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => openEqualizer(context),
            ),
            SwitchListTile(
              title: const Text('Экономия трафика'),
              subtitle: const Text('Лёгкий аудиопоток, если YouTube его отдаёт'),
              value: st.economy,
              onChanged: st.setEconomy,
            ),
            const SectionTitle('Загрузки'),
            ListenableBuilder(
              listenable: Offline.instance,
              builder: (context, _) {
                final o = Offline.instance;
                return ListTile(
                  leading: const Icon(Icons.download_done_rounded),
                  title: Text('Скачано: ${o.count} тр. · ${fmtBytes(o.bytes)}'),
                  subtitle: const Text('Хранятся внутри приложения и играют без интернета'),
                  trailing: o.count == 0
                      ? null
                      : TextButton(
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Очистить загрузки?'),
                                content: Text('Удалить ${o.count} тр. (${fmtBytes(o.bytes)}) из памяти телефона? '
                                    'Плейлисты и лайки останутся.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
                                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
                                ],
                              ),
                            );
                            if (ok == true) await o.clear();
                          },
                          child: const Text('Очистить'),
                        ),
                );
              },
            ),
            const SectionTitle('О приложении'),
            const ListTile(
              title: Text('ECHOES mobile — тестовая версия'),
              subtitle: Text('Музыка играет потоком и не сохраняется на телефон. '
                  'В памяти хранятся только списки: «Мне нравится», плейлисты и история.'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Фото для фона: из галереи (системный выбор фото iOS) или из «Файлов». Копия — во внутреннюю папку
/// приложения (оригинал может пропасть).
Future<void> _pickBackground(BuildContext context) async {
  final fromGallery = await showGlassSheet<bool>(
    context,
    (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.photo_library_rounded),
          title: const Text('Из галереи'),
          subtitle: const Text('Фото и картинки с телефона'),
          onTap: () => Navigator.pop(ctx, true),
        ),
        ListTile(
          leading: const Icon(Icons.folder_rounded),
          title: const Text('Из «Файлов»'),
          subtitle: const Text('iCloud Drive, загрузки, Telegram'),
          onTap: () => Navigator.pop(ctx, false),
        ),
      ]),
    ),
  );
  if (fromGallery == null || !context.mounted) return;
  final XFile? f;
  try {
    f = fromGallery ? await _fromGallery() : await _fromFiles();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось открыть фото: $e')));
    }
    return;
  }
  if (f == null) return;
  await _saveBackground(f);
}

/// Системная галерея iOS (PHPicker): разрешение на доступ ко всем фото не нужно — приложение получает
/// только выбранную картинку. Большие фото ужимаются до 2400 px — фону хватает, памяти меньше.
Future<XFile?> _fromGallery() => ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2400,
      maxHeight: 2400,
      imageQuality: 90,
      requestFullMetadata: false,
    );

Future<XFile?> _fromFiles() => openFile(acceptedTypeGroups: const [
      XTypeGroup(
        label: 'Фото',
        extensions: ['jpg', 'jpeg', 'png', 'heic', 'webp'],
        uniformTypeIdentifiers: ['public.image'],
      ),
    ]);

Future<void> _saveBackground(XFile f) async {
  final dir = await getApplicationSupportDirectory();
  final ext = f.name.contains('.') ? f.name.split('.').last.toLowerCase() : 'jpg';
  final dst = File('${dir.path}/background_${DateTime.now().millisecondsSinceEpoch}.$ext');
  await dst.writeAsBytes(await f.readAsBytes());
  final st = Store.instance;
  final old = st.bgPath;
  st.setBackground(dst.path);
  if (old != null && old != dst.path) {
    try {
      File(old).deleteSync();
    } catch (_) {}
  }
}

void _clearBackground(Store st) {
  final old = st.bgPath;
  st.setBackground(null);
  if (old != null) {
    try {
      File(old).deleteSync();
    } catch (_) {}
  }
}
