import 'dart:math' as math;

import 'package:echoes_eq/echoes_eq.dart';
import 'package:flutter/material.dart';

import '../glass.dart';
import '../services/store.dart';
import '../ui.dart';

/// Пресеты эквалайзера: дБ для полос 32, 64, 125, 250, 500 Гц, 1, 2, 4, 8, 16 кГц.
const eqPresets = <String, List<double>>{
  'Плоский': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  'Бас+': [6, 5.5, 4.5, 3, 1, 0, 0, 0, 0, 0],
  'Бас и верх': [5, 4, 2.5, 0, -1.5, -1.5, 0, 2.5, 4, 4.5],
  'Хип-хоп': [5.5, 5, 3, 1.5, -0.5, -1, 0.5, 1, 2, 2.5],
  'Электроника': [5, 4.5, 2, 0, -1.5, 1, 0.5, 2, 4, 5],
  'Рок': [4.5, 3.5, 2, 0, -1, -0.5, 1.5, 3, 4, 4.5],
  'Поп': [-1, 0, 1.5, 3, 4, 3, 1.5, 0, -0.5, -1],
  'Вокал': [-2, -2, -1, 1, 3, 4, 3.5, 2, 0, -1],
  'Джаз': [3, 2, 1, 1.5, -1, -1, 0, 1, 2, 3],
  'Классика': [3, 2.5, 1.5, 1, -1, -1, 0, 1.5, 2.5, 3],
  'Громкость': [4, 3, 1, 0, -1, 0, 0, 1, 3, 4],
  'Ночной': [-2, -1, 0, 1, 2, 2, 1.5, 0, -2, -3],
};

/// Предусиление для пресета: чем сильнее подъём, тем ниже общий уровень (чтобы не перегружать звук).
double presetPreamp(List<double> g) => -(g.reduce(math.max).clamp(0, 12) * 0.6).roundToDouble();

void openEqualizer(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const EqualizerScreen()));

/// Эквалайзер: вкл/выкл, пресеты, 10 полос (−12…+12 дБ) и предусиление. Меняется сразу, на играющем треке.
class EqualizerScreen extends StatelessWidget {
  const EqualizerScreen({super.key});

  static String _hz(int f) => f >= 1000 ? '${f ~/ 1000}к' : '$f';

  @override
  Widget build(BuildContext context) {
    final st = Store.instance;
    final dim = Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6);
    return Ambient(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Эквалайзер'),
          actions: [
            TextButton(
              onPressed: () => st.setEq(gains: eqPresets['Плоский'], preamp: 0, preset: 'Плоский'),
              child: const Text('Сбросить'),
            ),
          ],
        ),
        body: ListenableBuilder(
          listenable: st,
          builder: (context, _) {
            final on = st.eqEnabled;
            return ListView(
              padding: EdgeInsets.only(bottom: context.u(120)),
              children: [
                SwitchListTile(
                  title: const Text('Эквалайзер', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(on ? st.eqPreset : 'Выключен'),
                  value: on,
                  onChanged: (v) => st.setEq(enabled: v),
                ),
                SizedBox(height: context.u(4)),
                // пресеты — лентой
                SizedBox(
                  height: context.u(44) + MediaQuery.textScalerOf(context).scale(4),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: context.u(16)),
                    itemCount: eqPresets.length,
                    separatorBuilder: (_, __) => SizedBox(width: context.u(8)),
                    itemBuilder: (context, i) {
                      final name = eqPresets.keys.elementAt(i);
                      return ChoiceChip(
                        label: Text(name),
                        selected: st.eqPreset == name,
                        onSelected: (_) {
                          final g = eqPresets[name]!;
                          st.setEq(gains: g, preamp: presetPreamp(g), preset: name, enabled: true);
                        },
                      );
                    },
                  ),
                ),
                SizedBox(height: context.u(12)),
                Opacity(
                  opacity: on ? 1 : 0.45,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: context.u(8)),
                    child: SizedBox(
                      height: context.u(260),
                      child: Row(children: [
                        for (var i = 0; i < 10; i++)
                          Expanded(
                            child: Column(children: [
                              Text(
                                '${st.eqGains[i] > 0 ? '+' : ''}${st.eqGains[i].toStringAsFixed(st.eqGains[i] % 1 == 0 ? 0 : 1)}',
                                style: TextStyle(fontSize: 11, color: dim),
                              ),
                              Expanded(
                                child: RotatedBox(
                                  quarterTurns: 3,
                                  child: Slider(
                                    value: st.eqGains[i],
                                    min: -12,
                                    max: 12,
                                    divisions: 48,
                                    onChanged: (v) {
                                      final g = List.of(st.eqGains)..[i] = v;
                                      st.setEq(gains: g, preset: 'Свой', enabled: true);
                                    },
                                  ),
                                ),
                              ),
                              Text(_hz(EchoesEq.frequencies[i]), style: TextStyle(fontSize: 11, color: dim)),
                            ]),
                          ),
                      ]),
                    ),
                  ),
                ),
                SizedBox(height: context.u(10)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: context.u(16)),
                  child: Row(children: [
                    const Text('Уровень'),
                    Expanded(
                      child: Slider(
                        value: st.eqPreamp.clamp(-12, 6),
                        min: -12,
                        max: 6,
                        divisions: 36,
                        onChanged: (v) => st.setEq(preamp: v),
                      ),
                    ),
                    SizedBox(
                      width: context.u(52),
                      child: Text('${st.eqPreamp > 0 ? '+' : ''}${st.eqPreamp.toStringAsFixed(1)} дБ',
                          textAlign: TextAlign.end, style: TextStyle(color: dim, fontSize: 12)),
                    ),
                  ]),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(context.u(16), context.u(12), context.u(16), 0),
                  child: Text(
                    'Действует на обычные потоки и скачанные треки. Часть треков SoundCloud приходит потоком HLS — '
                    'iOS не даёт его обрабатывать, они играют без эквалайзера.',
                    style: TextStyle(color: dim, fontSize: 12),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
