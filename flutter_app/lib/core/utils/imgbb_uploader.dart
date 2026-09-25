import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

/// Uploads images to ImgBB and returns the public image URL.
///
/// The key is read from the local `.env` file (git-ignored) at runtime:
///
/// ```bash
/// IMGBB_API_KEY=your_key
/// ```
///
/// A `--dart-define=IMGBB_API_KEY=...` value still works as a fallback
/// (e.g. for CI), and the `.env` key wins when both are present.
///
/// ImgBB URLs are public. KeepIt stores only the returned URL in Hive and
/// Firestore; the image bytes never go into a Firestore document.
class ImgBbUploader {
  ImgBbUploader._();

  static String get _apiKey =>
      dotenv.env['IMGBB_API_KEY'] ??
      const String.fromEnvironment('IMGBB_API_KEY');

  static final Uri _endpoint = Uri.parse('https://api.imgbb.com/1/upload');
  static const int _maxBytes = 32 * 1024 * 1024;

  static bool get isConfigured => _apiKey.trim().isNotEmpty;

  static Future<String> upload(XFile image) async {
    if (!isConfigured) {
      throw const ImgBbUploadException(
        'Image upload is not configured. Build with IMGBB_API_KEY.',
      );
    }

    final bytes = await image.readAsBytes();
    if (bytes.isEmpty) {
      throw const ImgBbUploadException('The selected image is empty.');
    }
    if (bytes.length > _maxBytes) {
      throw const ImgBbUploadException(
        'Image is too large. Please choose an image under 32 MB.',
      );
    }

    final request = http.MultipartRequest('POST', _endpoint)
      ..fields['key'] = _apiKey
      ..files.add(
        http.MultipartFile.fromBytes(
          'image',
          bytes,
          filename: _safeFilename(image.name),
        ),
      );

    late final http.StreamedResponse response;
    try {
      response = await request.send().timeout(const Duration(seconds: 45));
    } catch (_) {
      throw const ImgBbUploadException(
        'Image upload failed. Check your internet connection.',
      );
    }

    final body = await response.stream.bytesToString();
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      throw const ImgBbUploadException('ImgBB returned an invalid response.');
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      final error = payload['error'];
      final message =
          error is Map ? error['message']?.toString() : error?.toString();
      throw ImgBbUploadException(
        message == null || message.isEmpty
            ? 'ImgBB rejected the image upload.'
            : 'ImgBB: $message',
      );
    }

    final data = payload['data'];
    final url = data is Map ? data['display_url'] ?? data['url'] : null;
    if (url is! String || url.trim().isEmpty) {
      throw const ImgBbUploadException('ImgBB did not return an image URL.');
    }
    return url.trim();
  }

  static String _safeFilename(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'keepit-image.jpg';
    return trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }
}

class ImgBbUploadException implements Exception {
  final String message;
  const ImgBbUploadException(this.message);

  @override
  String toString() => message;
}
