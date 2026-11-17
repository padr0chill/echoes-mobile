import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'net_protocol.dart';

class NetUnavailable implements Exception {
  const NetUnavailable();
}

class NetRelays {
  const NetRelays({
    this.urls = const [
      'wss://relay.damus.io',
      'wss://nos.lol',
      'wss://relay.primal.net',
      'wss://nostr.mom',
      'wss://relay.snort.social',
      'wss://nostr.oxtr.dev',
      'wss://relay.nostr.net',
      'wss://nostr-pub.wellorder.net',
    ],
    this.timeout = const Duration(seconds: 5),
  });

  final List<String> urls;
  final Duration timeout;

  Future<List<NetJson>> read(NetJson filter, {int budget = 160}) async {
    final responses = await Future.wait(
      urls.map((url) => _readRelay(url, filter, budget)),
    );
    if (responses.every((r) => r == null)) throw const NetUnavailable();
    final candidates = <(String, String, String), NetJson>{};
    for (final response in responses.nonNulls) {
      for (final event in response) {
        final key = (
          event['id'] as String,
          event['sig'] as String,
          _uniqueEventPayload(event),
        );
        candidates.putIfAbsent(key, () => event);
      }
    }
    final sorted = candidates.values.toList()..sort(_newestFirst);
    return compute(_verified, sorted.take(budget * 2).toList());
  }

  Future<int> publish(NetJson event) async {
    final responses = await Future.wait(
      urls.map(
        (url) => _connection(url, (socket, messages) async {
          socket.add(jsonEncode(['EVENT', event]));
          await for (final frame in messages) {
            final data = _frame(frame);
            if (data.length >= 3 && data[0] == 'OK' && data[1] == event['id']) {
              return data[2] == true;
            }
          }
          return false;
        }),
      ),
    );
    return responses.where((accepted) => accepted == true).length;
  }

  Future<List<NetJson>?> _readRelay(String url, NetJson filter, int budget) {
    final events = <NetJson>[];
    return _connection(url, (socket, messages) async {
      socket.add(jsonEncode(['REQ', 'echoes-mobile', filter]));
      await for (final frame in messages) {
        final data = _frame(frame);
        if (data.length < 2 || data[1] != 'echoes-mobile') continue;
        if (data[0] == 'EOSE') return events;
        if (data[0] == 'CLOSED') break;
        if (data[0] != 'EVENT' || data.length != 3) continue;
        final event = netObject(data[2]);
        if (netEventShape(event) && _matches(event, filter)) events.add(event);
        if (events.length >= budget) return events;
      }
      return events.isEmpty ? null : events;
    }, onTimeout: () => events.isEmpty ? null : events);
  }

  Future<T?> _connection<T>(
    String url,
    Future<T?> Function(WebSocket, Stream<dynamic>) operation, {
    T? Function()? onTimeout,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    WebSocket? socket;
    try {
      socket = await WebSocket.connect(
        url,
        customClient: client,
      ).timeout(timeout);
      return await operation(socket, socket).timeout(timeout);
    } on TimeoutException {
      return onTimeout?.call();
    } catch (_) {
      return null;
    } finally {
      if (socket != null) unawaited(socket.close().catchError((Object _) {}));
      client.close(force: true);
    }
  }
}

List<dynamic> _frame(dynamic value) {
  if (value is! String || value.length > 160000) return const [];
  try {
    final result = jsonDecode(value);
    return result is List ? result : const [];
  } on FormatException {
    return const [];
  }
}

bool _matches(NetJson event, NetJson filter) {
  if (filter['kinds'] case final List kinds when !kinds.contains(event['kind'])) {
    return false;
  }
  if (filter['authors'] case final List authors
      when !authors.contains(event['pubkey'])) {
    return false;
  }
  for (final entry in filter.entries.where(
    (entry) => entry.key.startsWith('#'),
  )) {
    final name = entry.key.substring(1);
    final wanted = entry.value as List;
    if (!(event['tags'] as List).any(
      (tag) => tag.length >= 2 && tag[0] == name && wanted.contains(tag[1]),
    )) {
      return false;
    }
  }
  return true;
}

String _uniqueEventPayload(NetJson e) => jsonEncode([
  e['pubkey'],
  e['created_at'],
  e['kind'],
  e['tags'],
  e['content'],
]);

int _newestFirst(NetJson a, NetJson b) {
  final time = (b['created_at'] as int).compareTo(a['created_at'] as int);
  return time == 0 ? (a['id'] as String).compareTo(b['id'] as String) : time;
}

List<NetJson> _verified(List<NetJson> events) {
  final valid = <String, NetJson>{};
  for (final event in events) {
    final id = event['id'] as String;
    if (!valid.containsKey(id) && netVerify(event)) valid[id] = event;
  }
  return valid.values.toList();
}
