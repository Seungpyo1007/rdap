import 'package:rdap/rdap.dart';

/// Prints registration data for each domain given on the command line:
///
///     dart run example/main.dart seungpyo.online google.com
Future<void> main(List<String> args) async {
  final rdap = RdapClient();
  try {
    for (final name in args.isEmpty ? ['seungpyo.online'] : args) {
      try {
        final domain = await rdap.domain(name);
        print(domain.ldhName);
        print('  registrar:   ${domain.registrarName ?? '-'}');
        print(
          '  expires:     ${domain.expires?.toIso8601String() ?? '-'}'
          ' (${domain.daysUntilExpiry() ?? '?'} days)',
        );
        print('  nameservers: ${domain.nameservers.join(', ')}');
        print('  status:      ${domain.status.join(', ')}');
      } on RdapException catch (error) {
        print('$name: ${error.code}: $error');
      }
    }
  } finally {
    rdap.close();
  }
}
