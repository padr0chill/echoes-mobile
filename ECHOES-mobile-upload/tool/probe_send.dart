// ignore_for_file: avoid_print
// Одна ссылка — разные способы запроса: http.get, Client.send(Request), повтор.
import 'package:echoes_mobile/services/yt.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final pick = await YtService.instance.stream('x1ZtIVuHph0');
  final u = pick.url;
  Future<int> viaGet() async => (await http.get(u, headers: {'Range': 'bytes=0-65535'})).statusCode;
  Future<int> viaSend(http.Client c) async {
    final r = await c.send(http.Request('GET', u)..headers['Range'] = 'bytes=0-65535');
    await r.stream.drain<void>();
    print('   request headers sent: ${r.request?.headers}');
    return r.statusCode;
  }

  final c = http.Client();
  print('get #1: ${await viaGet()}');
  print('send #1: ${await viaSend(c)}');
  print('get #2: ${await viaGet()}');
  print('send new client: ${await viaSend(http.Client())}');
  final mid = pick.size ~/ 2;
  final r = await http.get(u, headers: {'Range': 'bytes=$mid-${mid + 32767}'});
  print('get middle: ${r.statusCode} ${r.bodyBytes.length}');
}
