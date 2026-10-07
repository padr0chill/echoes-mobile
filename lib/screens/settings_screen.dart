import 'package:flutter/material.dart';

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
          padding: EdgeInsets.only(bottom: context.u(120)),
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(context.u(16), context.u(16), context.u(16), 0),
              child: const Text('Настройки', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
            ),
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
            SwitchListTile(
              title: const Text('Экономия трафика'),
              subtitle: const Text('Лёгкий аудиопоток, если YouTube его отдаёт'),
              value: st.economy,
              onChanged: st.setEconomy,
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
