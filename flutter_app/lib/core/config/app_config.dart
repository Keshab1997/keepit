/// Store / legal configuration shown in the Profile screen.
///
/// The legal pages are served from GitHub Pages (`/docs` folder of this repo).
/// Enable it once: GitHub → Settings → Pages → Source: `main` / `/docs`.
class AppConfig {
  AppConfig._();

  static const String appName = 'KeepIt';
  static const String tagline = 'Your visual second brain';
  static const String packageName = 'com.keshab.keepit';

  static const String supportEmail = 'keshabsarkar1997@gmail.com';

  static const String _pagesBase = 'https://keshab1997.github.io/keepit';
  static const String privacyPolicyUrl = '$_pagesBase/privacy-policy.html';
  static const String termsUrl = '$_pagesBase/terms.html';
  static const String deleteAccountUrl = '$_pagesBase/delete-account.html';

  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=$packageName';
  static const String sourceUrl = 'https://github.com/Keshab1997/keepit';
}
