import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rdap/rdap.dart';
import 'package:test/test.dart';

final _bootstrapUri = Uri.parse('https://data.iana.org/rdap/dns.json');

final _bootstrap = <String, Object?>{
  'version': '1.0',
  'services': [
    [
      ['com', 'net'],
      ['https://rdap.verisign.com/com/v1/'],
    ],
    [
      ['online'],
      ['http://rdap.radix.host/rdap/', 'https://rdap.radix.host/rdap/'],
    ],
    [
      ['uk'],
      ['https://rdap.nominet.uk/uk/'],
    ],
    [
      ['co.uk'],
      ['https://couk.example/rdap'],
    ],
    [
      ['xn--3e0b707e'],
      ['https://rdap.kr.example/'],
    ],
  ],
};

// Trimmed from the live rdap.verisign.com response for google.com.
final _google = <String, Object?>{
  'objectClassName': 'domain',
  'ldhName': 'GOOGLE.COM',
  'status': ['client transfer prohibited', 'server delete prohibited'],
  'events': [
    {'eventAction': 'registration', 'eventDate': '1997-09-15T04:00:00Z'},
    {'eventAction': 'expiration', 'eventDate': '2028-09-14T04:00:00Z'},
    {'eventAction': 'last changed', 'eventDate': '2019-09-09T15:39:04Z'},
  ],
  'entities': [
    {
      'objectClassName': 'entity',
      'roles': ['registrar'],
      'publicIds': [
        {'type': 'IANA Registrar ID', 'identifier': '292'},
      ],
      'vcardArray': [
        'vcard',
        [
          ['version', {}, 'text', '4.0'],
          ['fn', {}, 'text', 'MarkMonitor Inc.'],
        ],
      ],
    },
  ],
  'secureDNS': {'delegationSigned': false},
  'nameservers': [
    {'objectClassName': 'nameserver', 'ldhName': 'NS1.GOOGLE.COM'},
    {'objectClassName': 'nameserver', 'ldhName': 'NS2.GOOGLE.COM'},
  ],
};

/// Serves the bootstrap registry and answers every other request with
/// [domain], recording the requested URLs.
MockClient _server(
  List<Uri> requests, {
  http.Response Function(http.Request request)? domain,
}) {
  return MockClient((request) async {
    requests.add(request.url);
    if (request.url == _bootstrapUri) {
      return http.Response(jsonEncode(_bootstrap), 200);
    }
    return domain?.call(request) ?? http.Response(jsonEncode(_google), 200);
  });
}

Matcher _throwsCode(String code) =>
    throwsA(isA<RdapException>().having((e) => e.code, 'code', code));

void main() {
  test('parses a domain from the bootstrapped server', () async {
    final requests = <Uri>[];
    final rdap = RdapClient(client: _server(requests));

    final domain = await rdap.domain('google.com');

    expect(
      requests.last.toString(),
      'https://rdap.verisign.com/com/v1/domain/google.com',
    );
    expect(domain.ldhName, 'google.com');
    expect(domain.status, contains('client transfer prohibited'));
    expect(domain.registered, DateTime.utc(1997, 9, 15, 4));
    expect(domain.expires, DateTime.utc(2028, 9, 14, 4));
    expect(domain.lastChanged, DateTime.utc(2019, 9, 9, 15, 39, 4));
    expect(domain.nameservers, ['ns1.google.com', 'ns2.google.com']);
    expect(domain.registrarName, 'MarkMonitor Inc.');
    expect(domain.registrarIanaId, '292');
    expect(domain.dnssecSigned, isFalse);
    expect(domain.raw['objectClassName'], 'domain');
    expect(domain.daysUntilExpiry(now: DateTime.utc(2028, 9, 4)), 10);
    expect(domain.daysUntilExpiry(now: DateTime.utc(2028, 9, 14, 3)), 0);
    expect(domain.daysUntilExpiry(now: DateTime.utc(2028, 9, 14, 5)), -1);
    expect(domain.daysUntilExpiry(now: DateTime.utc(2028, 10, 14, 4)), -30);
    expect(domain.isExpired(now: DateTime.utc(2028, 9, 14, 3)), isFalse);
    expect(domain.isExpired(now: DateTime.utc(2028, 9, 14, 5)), isTrue);
    expect(domain.unicodeName, isNull);
  });

  test('downloads the bootstrap registry once per client', () async {
    final requests = <Uri>[];
    final rdap = RdapClient(client: _server(requests));

    await Future.wait([rdap.domain('google.com'), rdap.domain('example.net')]);
    await rdap.domain('example.com');

    expect(requests.where((uri) => uri == _bootstrapUri), hasLength(1));
  });

  test(
    'prefers https and the longest suffix, and adds a missing slash',
    () async {
      final requests = <Uri>[];
      final rdap = RdapClient(client: _server(requests));

      await rdap.domain('example.online');
      expect(
        requests.last.toString(),
        'https://rdap.radix.host/rdap/domain/example.online',
      );

      await rdap.domain('example.co.uk');
      expect(
        requests.last.toString(),
        'https://couk.example/rdap/domain/example.co.uk',
      );
    },
  );

  test(
    'normalizes case and a trailing dot, and rejects malformed names',
    () async {
      final requests = <Uri>[];
      final rdap = RdapClient(client: _server(requests));

      await rdap.domain(' Google.COM. ');
      expect(requests.last.path, '/com/v1/domain/google.com');

      expect(() => rdap.domain('not a domain.com'), throwsFormatException);
      expect(() => rdap.domain('한국!.com'), throwsFormatException);
      expect(() => rdap.domain('localhost'), throwsFormatException);
    },
  );

  test('converts internationalized names to Punycode', () async {
    final requests = <Uri>[];
    final rdap = RdapClient(client: _server(requests));

    // Expected values from Python's idna codec.
    await rdap.domain('한국.com');
    expect(requests.last.path, '/com/v1/domain/xn--3e0b707e.com');

    await rdap.domain('Bücher.COM');
    expect(requests.last.path, '/com/v1/domain/xn--bcher-kva.com');

    await rdap.domain('도메인.한국');
    expect(
      requests.last.toString(),
      'https://rdap.kr.example/domain/xn--hq1bm8jm9l.xn--3e0b707e',
    );

    await rdap.domain('xn--3e0b707e.com');
    expect(requests.last.path, '/com/v1/domain/xn--3e0b707e.com');
  });

  test('reports a TLD missing from the bootstrap registry', () async {
    final requests = <Uri>[];
    final rdap = RdapClient(client: _server(requests));

    await expectLater(rdap.domain('naver.kr'), _throwsCode('unsupported_tld'));
    expect(requests, [_bootstrapUri]);
  });

  test('maps 404, other HTTP errors, and bad JSON to error codes', () async {
    final rdap404 = RdapClient(
      client: _server([], domain: (_) => http.Response('', 404)),
    );
    await expectLater(
      rdap404.domain('nope.com'),
      throwsA(
        isA<RdapException>()
            .having((e) => e.code, 'code', 'not_found')
            .having((e) => e.statusCode, 'statusCode', 404),
      ),
    );

    final rdap503 = RdapClient(
      client: _server([], domain: (_) => http.Response('', 503)),
    );
    await expectLater(rdap503.domain('google.com'), _throwsCode('http_error'));

    final rdapHtml = RdapClient(
      client: _server([], domain: (_) => http.Response('<html>', 200)),
    );
    await expectLater(
      rdapHtml.domain('google.com'),
      _throwsCode('invalid_response'),
    );

    final rdapNoName = RdapClient(
      client: _server([], domain: (_) => http.Response('{}', 200)),
    );
    await expectLater(
      rdapNoName.domain('google.com'),
      _throwsCode('invalid_response'),
    );
  });

  test('retries the bootstrap registry after a failure', () async {
    var bootstrapCalls = 0;
    final rdap = RdapClient(
      client: MockClient((request) async {
        if (request.url == _bootstrapUri && bootstrapCalls++ == 0) {
          return http.Response('', 500);
        }
        if (request.url == _bootstrapUri) {
          return http.Response(jsonEncode(_bootstrap), 200);
        }
        return http.Response(jsonEncode(_google), 200);
      }),
    );

    await expectLater(rdap.domain('google.com'), _throwsCode('http_error'));
    expect((await rdap.domain('google.com')).ldhName, 'google.com');
  });

  test('retries a request once when the connection drops', () async {
    var domainCalls = 0;
    MockClient dropping(int failures) => MockClient((request) async {
      if (request.url == _bootstrapUri) {
        return http.Response(jsonEncode(_bootstrap), 200);
      }
      if (domainCalls++ < failures) {
        throw http.ClientException(
          'Connection closed before full header was received',
          request.url,
        );
      }
      return http.Response(jsonEncode(_google), 200);
    });

    final once = RdapClient(client: dropping(1));
    expect((await once.domain('google.com')).ldhName, 'google.com');
    expect(domainCalls, 2);

    domainCalls = 0;
    final twice = RdapClient(client: dropping(2));
    await expectLater(twice.domain('google.com'), _throwsCode('http_error'));
    expect(domainCalls, 2);
  });

  test('times out slow servers', () async {
    final rdap = RdapClient(
      timeout: const Duration(milliseconds: 20),
      client: MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return http.Response('{}', 200);
      }),
    );

    await expectLater(rdap.domain('google.com'), _throwsCode('timeout'));
  });

  test('leaves optional fields null when the registry omits them', () {
    final domain = RdapDomain.fromJson({'ldhName': 'example.com'});

    expect(domain.expires, isNull);
    expect(domain.registrarName, isNull);
    expect(domain.dnssecSigned, isNull);
    expect(domain.nameservers, isEmpty);
    expect(domain.daysUntilExpiry(), isNull);
    expect(domain.isExpired(), isFalse);

    final idn = RdapDomain.fromJson({
      'ldhName': 'XN--3E0B707E.COM',
      'unicodeName': '한국.com',
    });
    expect(idn.ldhName, 'xn--3e0b707e.com');
    expect(idn.unicodeName, '한국.com');
  });
}
