import 'package:flutter_test/flutter_test.dart';
import 'package:iccms/core/errors/app_exception.dart';
import 'package:iccms/core/network/api_client.dart';

import '../helpers.dart';

class FakeTokens implements TokenSource {
  String? token = 'old';
  int refreshes = 0;
  String? next = 'new';

  @override
  String? get accessToken => token;

  @override
  Future<String?> refresh() async {
    refreshes++;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    token = next;
    return next;
  }
}

ApiClient client(FakeAdapter a, FakeTokens t, {List<Duration>? sleeps}) => ApiClient(
      baseUrl: 'http://api.test/api/v1',
      adapter: a,
      tokens: t,
      info: ClientInfo(flavor: 'driver', versionCode: 7, deviceId: 'dev-1', language: () => 'hi'),
      sleep: (d) async => sleeps?.add(d),
      random: () => 0,
    );

Future<AppException> caught(Future<dynamic> f) async {
  try {
    await f;
  } on AppException catch (e) {
    return e;
  }
  throw StateError('expected an AppException');
}

void main() {
  test('sends the Section 6.1 headers and the bearer token', () async {
    final a = FakeAdapter((m, p, o) => (200, {'ok': true}));
    await client(a, FakeTokens()).get('/me');
    final h = a.requests.single.headers;
    expect(h['X-App-Flavor'], 'driver');
    expect(h['X-App-Version-Code'], '7');
    expect(h['X-Device-Id'], 'dev-1');
    expect(h['Accept-Language'], 'hi');
    expect(h['Authorization'], 'Bearer old');
  });

  test('401: ten concurrent requests trigger ONE refresh, then each is retried once with the new token', () async {
    final a = FakeAdapter((m, p, o) => o.headers['Authorization'] == 'Bearer new' ? (200, {'path': p}) : (401, envelope('UNAUTHORIZED')));
    final t = FakeTokens();
    final c = client(a, t);
    final results = await Future.wait(List.generate(10, (i) => c.get('/trips/$i')));
    expect(t.refreshes, 1);
    expect(c.refreshCount, 1);
    expect(results.map((r) => (r as Map)['path']), List.generate(10, (i) => '/trips/$i'));
    expect(a.requests.length, 20); // each request: once with the old token, once with the new
  });

  test('401 after the retry (or a failed refresh) is not retried again', () async {
    final a = FakeAdapter((m, p, o) => (401, envelope('UNAUTHORIZED')));
    final t = FakeTokens()..next = null;
    await expectLater(client(a, t).get('/me'), throwsA(isA<AppException>().having((e) => e.status, 'status', 401)));
    expect(a.requests.length, 1);
    final t2 = FakeTokens();
    await expectLater(client(a, t2).get('/me'), throwsA(isA<AppException>()));
    expect(t2.refreshes, 1);
  });

  test('GET is retried with backoff on network / 5xx (3 tries); POST never', () async {
    var calls = 0;
    final a = FakeAdapter((m, p, o) {
      calls++;
      return calls < 3 ? (calls == 1 ? (0, null) : (503, envelope('UNAVAILABLE'))) : (200, {'ok': true});
    });
    final sleeps = <Duration>[];
    expect(await client(a, FakeTokens(), sleeps: sleeps).get('/trips'), {'ok': true});
    expect(calls, 3);
    expect(sleeps, [const Duration(milliseconds: 200), const Duration(milliseconds: 400)]);

    calls = 0;
    final b = FakeAdapter((m, p, o) {
      calls++;
      return (503, envelope('UNAVAILABLE'));
    });
    await expectLater(client(b, FakeTokens()).post('/sync', body: {}), throwsA(isA<AppException>().having((e) => e.status, 'status', 503)));
    expect(calls, 1);
    calls = 0;
    await expectLater(client(b, FakeTokens()).get('/x'), throwsA(isA<AppException>()));
    expect(calls, 3);
  });

  test('error envelope → AppException(code, message, details); no response → NETWORK', () async {
    final a = FakeAdapter((m, p, o) => (409, {'error': {'code': 'EDIT_WINDOW_CLOSED', 'message': 'Too late', 'details': {'minutes': 30}}}));
    final e = await caught(client(a, FakeTokens()).patch('/batches/1'));
    expect([e.code, e.message, e.status, e.details['minutes']], ['EDIT_WINDOW_CLOSED', 'Too late', 409, 30]);
    expect(e.isPermanent, isTrue);
    final off = FakeAdapter((m, p, o) => (0, null));
    final n = await caught(client(off, FakeTokens()).post('/sync'));
    expect([n.code, n.status, n.isTransient], ['NETWORK', null, true]);
  });

  test('426 emits UpgradeRequired; WRONG_APP_FOR_ROLE / SESSION_ON_OTHER_DEVICE emit SessionRevoked', () async {
    final a = FakeAdapter((m, p, o) => switch (p) {
          '/old' => (426, envelope('UPGRADE_REQUIRED')),
          '/role' => (403, envelope('WRONG_APP_FOR_ROLE')),
          '/device' => (409, envelope('SESSION_ON_OTHER_DEVICE')),
          _ => (403, envelope('FORBIDDEN_ROLE')),
        });
    final c = client(a, FakeTokens());
    final events = <ApiEvent>[];
    c.events.listen(events.add);
    for (final p in ['/old', '/role', '/device', '/other']) {
      await c.post(p).catchError((_) => null);
    }
    await Future<void>.delayed(Duration.zero);
    expect(events.map((e) => e.runtimeType.toString()), ['UpgradeRequiredEvent', 'SessionRevokedEvent', 'SessionRevokedEvent']);
    expect((events[1] as SessionRevokedEvent).error.code, 'WRONG_APP_FOR_ROLE');
  });
}
