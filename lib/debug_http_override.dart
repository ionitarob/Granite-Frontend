import 'dart:io';
import 'package:flutter/foundation.dart';

/// Dev-only HttpOverrides that accept self-signed certificates for the
/// provided host allow-list. This must only be enabled in debug builds.
class DevHttpOverrides extends HttpOverrides {
  final List<String>? allowBadCertificateForHosts;

  DevHttpOverrides([this.allowBadCertificateForHosts]);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    if (!kDebugMode) return client;

    client.badCertificateCallback = (X509Certificate cert, String host, int port) {
      final list = allowBadCertificateForHosts ?? [];
      if (list.isEmpty) return true;
      return list.contains(host);
    };
    return client;
  }
}
