import 'package:url_launcher/url_launcher.dart';

class ExternalLinkLauncher {
  static Future<void> openSource(String? urlString) async {
    if (urlString == null || urlString.isEmpty) return;

    final uri = Uri.parse(urlString.trim());

    // 1. Try opening directly in the native host app (Instagram, YouTube, Twitter, etc.)
    final bool launchedInApp = await launchUrl(
      uri,
      mode: LaunchMode.externalNonBrowserApplication,
    ).catchError((_) => false);

    // 2. If native app is not installed, fallback to external browser (Chrome / Safari)
    if (!launchedInApp) {
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      ).catchError((_) => false);
    }
  }
}
