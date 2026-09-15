## 0.0.2

* Look up internationalized domain names such as `한국.com`. Unicode labels
  are converted to Punycode before the lookup.
* Add `RdapDomain.unicodeName` and `RdapDomain.isExpired`.
* Add pub.dev and CI badges to the README.

## 0.0.1

* Initial release.
* `RdapClient.domain` looks up registration data, discovering the registry
  server from the IANA bootstrap registry.
* `RdapDomain` exposes expiration, registration, and last-changed dates,
  registrar name and IANA ID, nameservers, status, DNSSEC delegation, and the
  raw response.
* `RdapException` reports `unsupported_tld`, `not_found`, `timeout`,
  `http_error`, and `invalid_response`.
