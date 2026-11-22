/// One rule for "is this the same link?", shared by every place that has to
/// answer it: the quick-add sheet, the clipboard banner, the share capture,
/// `addUrl`'s duplicate check and backup import.
///
/// It used to live inside `MindFeedController`. Import needs it too, and a
/// second copy in `DataImport` would drift the moment either side is tuned -
/// then restoring a backup would happily re-add links the app itself considers
/// duplicates.
class UrlNormalization {
  UrlNormalization._();

  /// Normalized form of [text], tolerating a pasted blob around the link.
  static String key(String text) => normalize(extract(text));

  /// True when two links point at the same page.
  static bool same(String url1, String url2) => key(url1) == key(url2);

  /// The first `http(s)://…` token in [text], or [text] itself when there is
  /// no URL in it (a bare `example.com/a` is still worth normalizing).
  static String extract(String text) {
    final urlRegex = RegExp(r'(https?://[^\s]+)');
    final match = urlRegex.firstMatch(text);
    return match != null ? match.group(0)! : text;
  }

  /// Scheme, `www.`, tracking parameters and trailing slashes are not meaning.
  static String normalize(String url) {
    var clean = url.trim().toLowerCase();
    clean = foldSchemeAndHost(clean);
    if (clean.contains('?')) {
      final parts = clean.split('?');
      var base = parts[0];
      while (base.endsWith('/')) {
        base = base.substring(0, base.length - 1);
      }
      final query = parts[1];
      final cleanParams = query.split('&').where((param) {
        return !param.startsWith('igsh=') &&
            !param.startsWith('si=') &&
            !param.startsWith('utm_') &&
            !param.startsWith('fbclid=');
      }).join('&');
      clean = cleanParams.isNotEmpty ? '$base?$cleanParams' : base;
    }
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    return clean;
  }

  /// `http://www.Example.com/a` and `https://example.com/a` are one page.
  ///
  /// Everything before the first `/` after the authority is lower-cased and
  /// stripped of a leading `http://`/`https://` and a leading `www.`. Only the
  /// authority is touched - the path keeps its case, because many sites are
  /// case-sensitive there.
  static String foldSchemeAndHost(String url) {
    final schemeEnd = url.indexOf('://');
    final authorityStart = schemeEnd >= 0 ? schemeEnd + 3 : 0;
    if (schemeEnd < 0) return url;

    final pathStart = url.indexOf('/', authorityStart);
    final authority = pathStart < 0
        ? url.substring(authorityStart)
        : url.substring(authorityStart, pathStart);
    final rest = pathStart < 0 ? '' : url.substring(pathStart);
    if (authority.isEmpty) return url;

    final host =
        authority.startsWith('www.') ? authority.substring(4) : authority;
    if (host.isEmpty) return url;
    return 'https://$host$rest';
  }
}
