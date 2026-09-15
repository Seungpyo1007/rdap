<h1 align="center">rdap</h1>

<p align="center">
  <a href="https://pub.dev/packages/rdap"><img src="https://img.shields.io/pub/v/rdap" alt="pub version"></a>
  <a href="https://pub.dev/packages/rdap/score"><img src="https://img.shields.io/pub/points/rdap" alt="pub points"></a>
  <a href="https://github.com/Seungpyo1007/rdap/actions/workflows/ci.yml"><img src="https://github.com/Seungpyo1007/rdap/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/Seungpyo1007/rdap/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license"></a>
</p>

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
- Internationalized names such as `한국.com` are converted to Punycode
  (`xn--3e0b707e.com`), and `unicodeName` returns the Unicode form when the
  registry publishes it.
- `raw` keeps the full response for fields the model does not cover.

## Installation

```yaml
dependencies:
  rdap: ^0.0.2
```

## Usage

```dart
final rdap = RdapClient(timeout: const Duration(seconds: 5));
try {
  final domain = await rdap.domain('example.com');
  if (domain.isExpired()) {
    print('${domain.ldhName} has expired');
  } else if ((domain.daysUntilExpiry() ?? 999) < 30) {
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
- Internationalized names are converted with Punycode only; UTS 46 mapping is
  not applied, so separate labels with `.` rather than a full-width `。`.
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
