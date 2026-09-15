/// Registration data for one domain name.
class RdapDomain {
  /// Creates registration data.
  const RdapDomain({
    required this.ldhName,
    this.unicodeName,
    this.status = const <String>[],
    this.registered,
    this.expires,
    this.lastChanged,
    this.nameservers = const <String>[],
    this.registrarName,
    this.registrarIanaId,
    this.dnssecSigned,
    this.raw = const <String, Object?>{},
  });

  /// Parses an RDAP domain object (RFC 9083 section 5.3).
  ///
  /// Throws a [FormatException] when `ldhName` is missing.
  factory RdapDomain.fromJson(Map<String, Object?> json) {
    final ldhName = json['ldhName'];
    if (ldhName is! String || ldhName.isEmpty) {
      throw const FormatException('Missing ldhName.');
    }

    final events = <String, DateTime>{};
    for (final event in _list(json['events']).whereType<Map>()) {
      final action = event['eventAction'];
      final date = DateTime.tryParse('${event['eventDate']}');
      if (action is String && date != null) {
        events.putIfAbsent(action, () => date);
      }
    }

    final registrar = _list(json['entities'])
        .whereType<Map>()
        .where((entity) => _list(entity['roles']).contains('registrar'))
        .firstOrNull;
    final secureDns = json['secureDNS'];
    final signed = secureDns is Map ? secureDns['delegationSigned'] : null;
    final unicodeName = json['unicodeName'];

    return RdapDomain(
      ldhName: ldhName.toLowerCase(),
      unicodeName: unicodeName is String && unicodeName.isNotEmpty
          ? unicodeName
          : null,
      status: _list(json['status']).whereType<String>().toList(growable: false),
      registered: events['registration'],
      expires: events['expiration'],
      lastChanged: events['last changed'],
      nameservers: _list(json['nameservers'])
          .whereType<Map>()
          .map((server) => server['ldhName'])
          .whereType<String>()
          .map((name) => name.toLowerCase())
          .toList(growable: false),
      registrarName: registrar == null
          ? null
          : _vcardName(registrar['vcardArray']),
      registrarIanaId: registrar == null
          ? null
          : _ianaId(registrar['publicIds']),
      dnssecSigned: signed is bool ? signed : null,
      raw: json,
    );
  }

  /// Domain name in lowercase ASCII (LDH) form, with Punycode labels.
  final String ldhName;

  /// Domain name in Unicode, such as `한국.com`, when the registry publishes
  /// it.
  final String? unicodeName;

  /// EPP status values such as `client transfer prohibited`.
  final List<String> status;

  /// Registration time, when published.
  final DateTime? registered;

  /// Expiration time, when published.
  final DateTime? expires;

  /// Time of the last registry change, when published.
  final DateTime? lastChanged;

  /// Delegated nameservers in lowercase.
  final List<String> nameservers;

  /// Registrar name from the registrar entity's vCard.
  final String? registrarName;

  /// IANA Registrar ID, when published.
  final String? registrarIanaId;

  /// Whether the delegation is DNSSEC-signed, when published.
  final bool? dnssecSigned;

  /// The full RDAP response for fields this class does not model.
  final Map<String, Object?> raw;

  /// Whole days left until [expires], rounded down so the value turns negative
  /// as soon as the domain expires, or `null` when the registry publishes no
  /// expiration date.
  int? daysUntilExpiry({DateTime? now}) {
    final left = expires?.difference(now ?? DateTime.now());
    if (left == null) return null;
    return (left.inMicroseconds / Duration.microsecondsPerDay).floor();
  }

  /// Whether [expires] has passed; `false` when the registry publishes no
  /// expiration date.
  bool isExpired({DateTime? now}) =>
      expires != null && (now ?? DateTime.now()).isAfter(expires!);
}

List<Object?> _list(Object? value) => value is List ? value : const <Object?>[];

String? _vcardName(Object? vcard) {
  if (vcard is! List || vcard.length < 2) return null;
  for (final property in _list(vcard[1])) {
    if (property is List && property.length >= 4 && property[0] == 'fn') {
      final value = property[3];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
  }
  return null;
}

String? _ianaId(Object? publicIds) {
  for (final id in _list(publicIds).whereType<Map>()) {
    if ('${id['type']}'.contains('IANA') && id['identifier'] != null) {
      return '${id['identifier']}';
    }
  }
  return null;
}
