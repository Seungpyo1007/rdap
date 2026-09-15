# rdap

Look up who registered a domain and when it expires, using
[RDAP](https://www.icann.org/rdap), the JSON successor to WHOIS. The client
finds the right registry server from the IANA bootstrap registry, so there is
no API key and no third-party service in between.

```dart
final rdap = RdapClient();
final domain = await rdap.domain('google.com');

print(domain.expires);           // 2028-09-14 04:00:00.000Z
print(domain.daysUntilExpiry()); // e.g. 729
print(domain.registrarName);     // MarkMonitor Inc.
print(domain.nameservers);       // [ns1.google.com, ns2.google.com, ...]

rdap.close();
```

## Platform support

Pure Dart on top of `package:http`: Dart VM, Flutter on Android, iOS, Windows,
macOS, Linux, and the web. The IANA registry and the major registries (Verisign
for `.com`/`.net`, Public Interest Registry for `.org`, Google Registry for
`.dev`) send `Access-Control-Allow-Origin: *`, so browser lookups work for
them. A smaller registry without CORS headers can only be reached from a
native app or a server.

## Features

- Expiration, registration, and last-changed dates as `DateTime`.
- Registrar name and IANA Registrar ID, nameservers, EPP status values, and
  DNSSEC delegation.
- Server discovery through the IANA bootstrap registry (RFC 9224), downloaded
  once per client and retried if it fails.
- Stable error codes: `unsupported_tld`, `not_found`, `timeout`, `http_error`,
  and `invalid_response`.
- `raw` keeps the full response for fields the model does not cover.

## Installation

```yaml
dependencies:
  rdap: ^0.0.1
```

## Usage

```dart
final rdap = RdapClient(timeout: const Duration(seconds: 5));
try {
  final domain = await rdap.domain('example.com');
  if ((domain.daysUntilExpiry() ?? 999) < 30) {
    print('${domain.ldhName} expires soon');
  }
} on RdapException catch (error) {
  switch (error.code) {
    case 'not_found':
      print('Not registered');
    case 'unsupported_tld':
      print('This TLD has no RDAP server');
    default:
      print(error);
  }
} finally {
  rdap.close();
}
```

Pass your own `http.Client` to share connections or to mock requests in tests.
An injected client is not closed by `close()`.

## Limitations

- Only TLDs listed in the IANA bootstrap registry are supported (about 1,200).
  Many country-code TLDs, including `.kr`, `.io`, and `.jp`, are not listed
  and fail with `unsupported_tld`.
- Names must be ASCII. Convert internationalized names to punycode
  (`xn--...`) first.
- Registries rate-limit RDAP. Cache results instead of polling.
- Registries redact personal contact data, so registrant details are usually
  absent.

## Flutter example

```dart
FutureBuilder<RdapDomain>(
  future: rdap.domain('seungpyo.online'),
  builder: (context, snapshot) {
    final domain = snapshot.data;
    if (domain == null) return const LinearProgressIndicator();
    return ListTile(
      title: Text(domain.ldhName),
      subtitle: Text('Expires in ${domain.daysUntilExpiry()} days'),
    );
  },
)
```
