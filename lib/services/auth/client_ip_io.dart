import 'dart:io';

Future<String?> getLocalIpAddress() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.any,
      includeLoopback: false,
    );

    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (address.type == InternetAddressType.IPv4 &&
            !address.isLoopback &&
            address.address.isNotEmpty) {
          return address.address;
        }
      }
    }
  } catch (_) {
    // Fall back to caller defaults.
  }

  return '127.0.0.1';
}
