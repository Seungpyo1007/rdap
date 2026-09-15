import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'rdap_domain.dart';

/// Looks up domain registration data over RDAP.
///
/// The RDAP server for each top-level domain is discovered from the IANA
/// bootstrap registry, which is downloaded once per client and reused.
class RdapClient {
  /// Creates an RDAP client.
  ///
  /// Each HTTP request fails with an [RdapException] whose code is `timeout`
  /// after [timeout].
  RdapClient({
    http.Client? client,
    Uri? bootstrapUri,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       bootstrapUri =
           bootstrapUri ?? Uri.parse('https://data.iana.org/rdap/dns.json');

  final http.Client _client;
  final bool _ownsClient;
  Future<Map<String, List<Uri>>>? _bootstrap;

  /// IANA bootstrap registry for domain names.
  final Uri bootstrapUri;

  /// Time limit for each HTTP request.
  final Duration timeout;

  /// Closes the HTTP client this instance created. An injected client is left
  /// open for its owner.
  void close() {
    if (_ownsClient) _client.close();
  }

  /// Looks up the registration data for [domain], such as `example.com`.
  ///
  /// Throws a [FormatException] when [domain] is not an ASCII domain name, and
  /// an [RdapException] when the lookup fails.
  Future<RdapDomain> domain(String domain) async {
    final name = _normalize(domain);
    final services = await (_bootstrap ??= _loadBootstrap());
    final base = _baseUriFor(services, name);
    if (base == null) {
      throw RdapException(
        'No RDAP server is registered for .${name.split('.').last}.',
        code: 'unsupported_tld',
      );
    }
    final path = base.path.endsWith('/') ? base.path : '${base.path}/';
    final json = await _getJson(
      base.replace(path: '${path}domain/$name'),
      domain: name,
    );
    try {
      return RdapDomain.fromJson(json);
    } on FormatException catch (error) {
      throw RdapException(
        'Invalid RDAP response for $name: ${error.message}',
        code: 'invalid_response',
      );
    }
  }

  Future<Map<String, List<Uri>>> _loadBootstrap() async {
    try {
      return _parseBootstrap(await _getJson(bootstrapUri));
    } catch (_) {
      // Let the next lookup retry instead of caching the failure.
      _bootstrap = null;
      rethrow;
    }
  }

  Future<Map<String, Object?>> _getJson(Uri uri, {String? domain}) async {
    Future<http.Response> get() => _client
        .get(
          uri,
          headers: const <String, String>{
            'accept': 'application/rdap+json, application/json',
          },
        )
        .timeout(timeout);

    final http.Response response;
    try {
      // Registries such as Verisign close idle keep-alive connections, so a
      // reused connection can fail before any header arrives. GET is
      // idempotent: retry once on a fresh connection.
      response = await get().onError<http.ClientException>((_, _) => get());
    } on TimeoutException {
      throw RdapException('Request to ${uri.host} timed out.', code: 'timeout');
    } on http.ClientException catch (error) {
      throw RdapException(
        'Request to ${uri.host} failed: ${error.message}',
        code: 'http_error',
      );
    }
    if (domain != null && response.statusCode == 404) {
      throw RdapException(
        '$domain is not registered.',
        statusCode: 404,
        code: 'not_found',
      );
    }
    if (response.statusCode != 200) {
      throw RdapException(
        '${uri.host} returned HTTP ${response.statusCode}.',
        statusCode: response.statusCode,
        code: 'http_error',
      );
    }
    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is Map<String, Object?>) return json;
    } on FormatException {
      // Reported below.
    }
    throw RdapException(
      '${uri.host} returned a response that is not a JSON object.',
      code: 'invalid_response',
    );
  }
}

/// RDAP lookup failure.
class RdapException implements Exception {
  /// Creates a lookup failure.
  const RdapException(this.message, {required this.code, this.statusCode});

  /// Safe error description.
  final String message;

  /// Stable error code: `unsupported_tld`, `not_found`, `timeout`,
  /// `http_error`, or `invalid_response`.
  final String code;

  /// HTTP status code, when the server answered.
  final int? statusCode;

  @override
  String toString() => message;
}

String _normalize(String domain) {
  final name = domain.trim().toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  // ponytail: Unicode (IDN) names need punycode first; add an encoder when
  // someone asks for it.
  if (!RegExp(r'^[a-z0-9-]+(\.[a-z0-9-]+)+$').hasMatch(name)) {
    throw FormatException('Not an ASCII domain name.', domain);
  }
  return name;
}

Map<String, List<Uri>> _parseBootstrap(Map<String, Object?> json) {
  final services = json['services'];
  if (services is! List) {
    throw const RdapException(
      'The IANA bootstrap registry has no services list.',
      code: 'invalid_response',
    );
  }
  final byTld = <String, List<Uri>>{};
  for (final service in services) {
    if (service is! List || service.length < 2) continue;
    final [tlds, urls, ...] = service;
    if (tlds is! List || urls is! List) continue;
    final uris = urls.map((url) => Uri.tryParse('$url')).nonNulls;
    final ordered = <Uri>[
      ...uris.where((uri) => uri.scheme == 'https'),
      ...uris.where((uri) => uri.scheme != 'https'),
    ];
    if (ordered.isEmpty) continue;
    for (final tld in tlds) {
      byTld['$tld'.toLowerCase()] = ordered;
    }
  }
  return byTld;
}

Uri? _baseUriFor(Map<String, List<Uri>> services, String name) {
  final labels = name.split('.');
  // Longest registered suffix wins, e.g. `co.uk` before `uk`.
  for (var i = 1; i < labels.length; i++) {
    final uris = services[labels.sublist(i).join('.')];
    if (uris != null) return uris.first;
  }
  return null;
}
