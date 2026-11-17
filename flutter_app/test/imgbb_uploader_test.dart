import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:keepit/core/utils/imgbb_uploader.dart';

/// Saving an image is a one-shot upload: if the response shape changes, the
/// user gets a generic error and the photo is lost from their library. These
/// tests pin the success path and every failure message.
void main() {
  XFile image(List<int> bytes, {String name = 'cat.jpg'}) =>
      XFile.fromData(Uint8List.fromList(bytes), name: name);

  http.Client respondWith(
    Object body, {
    int status = 200,
    void Function(http.BaseRequest request)? inspect,
  }) {
    return MockClient((request) async {
      inspect?.call(request);
      final encoded = body is String ? body : jsonEncode(body);
      return http.Response(encoded, status,
          headers: {'content-type': 'application/json'});
    });
  }

  setUp(() {
    ImgBbUploader.resetClient();
    dotenv.testLoad(mergeWith: {'IMGBB_API_KEY': 'test-key'});
  });

  tearDown(() {
    ImgBbUploader.resetClient();
    dotenv.clean();
  });

  test('a successful upload returns the public URL', () async {
    http.Request? seen;
    ImgBbUploader.client = respondWith(
      {
        'success': true,
        'data': {
          'display_url': 'https://i.ibb.co/abc/cat.jpg',
          'url': 'https://i.ibb.co/abc/cat.jpg',
        },
      },
      inspect: (request) => seen = request as http.Request,
    );

    final url = await ImgBbUploader.upload(image([1, 2, 3]));

    expect(url, 'https://i.ibb.co/abc/cat.jpg');
    expect(seen!.url.toString(), 'https://api.imgbb.com/1/upload');
    expect(seen!.method, 'POST');
    // A multipart body carries the API key and the file part.
    expect(
      seen!.headers['content-type'],
      startsWith('multipart/form-data; boundary='),
      reason: 'the key and the file travel as a multipart form',
    );
  });

  test('falls back to `url` when `display_url` is absent', () async {
    ImgBbUploader.client = respondWith({
      'success': true,
      'data': {'url': 'https://i.ibb.co/xyz/cat.jpg'},
    });

    expect(
        await ImgBbUploader.upload(image([1])), 'https://i.ibb.co/xyz/cat.jpg');
  });

  test('an unsafe filename is sanitised before upload', () async {
    http.Request? seen;
    ImgBbUploader.client = respondWith(
      {
        'success': true,
        'data': {'url': 'https://i.ibb.co/1/x.jpg'},
      },
      inspect: (request) => seen = request as http.Request,
    );

    await ImgBbUploader.upload(
      image([1], name: '../../etc/my photo (1).jpg'),
    );

    // The multipart body is streamed, so assert on the sanitiser itself.
    expect(seen!.headers['content-type'], startsWith('multipart/form-data'));
    expect(ImgBbUploader.safeFilename('../../etc/my photo (1).jpg'),
        '.._.._etc_my_photo__1_.jpg');
  });

  test('a rejected upload surfaces ImgBB’s own message', () async {
    ImgBbUploader.client = respondWith(
      {
        'success': false,
        'error': {'message': 'Invalid API key'},
      },
      status: 400,
    );

    await expectLater(
      ImgBbUploader.upload(image([1])),
      throwsA(isA<ImgBbUploadException>().having(
        (e) => e.message,
        'message',
        'ImgBB: Invalid API key',
      )),
    );
  });

  test('a rejection without a message still explains itself', () async {
    ImgBbUploader.client = respondWith({'success': false}, status: 400);

    await expectLater(
      ImgBbUploader.upload(image([1])),
      throwsA(isA<ImgBbUploadException>().having(
          (e) => e.message, 'message', 'ImgBB rejected the image upload.')),
    );
  });

  test('a non-JSON response is reported, not thrown raw', () async {
    ImgBbUploader.client = respondWith('<html>captcha</html>');

    await expectLater(
      ImgBbUploader.upload(image([1])),
      throwsA(isA<ImgBbUploadException>().having(
          (e) => e.message, 'message', 'ImgBB returned an invalid response.')),
    );
  });

  test('success without any URL is an error, never an empty card', () async {
    ImgBbUploader.client = respondWith({'success': true, 'data': {}});

    await expectLater(
      ImgBbUploader.upload(image([1])),
      throwsA(isA<ImgBbUploadException>().having(
          (e) => e.message, 'message', 'ImgBB did not return an image URL.')),
    );
  });

  test('an empty file is rejected before any request is made', () async {
    var called = false;
    ImgBbUploader.client = MockClient((request) async {
      called = true;
      return http.Response('{}', 200);
    });

    await expectLater(
      ImgBbUploader.upload(image([])),
      throwsA(isA<ImgBbUploadException>()),
    );
    expect(called, isFalse);
  });

  test('a network failure becomes a friendly message', () async {
    ImgBbUploader.client = MockClient((request) async {
      throw const SocketExceptionStub();
    });

    await expectLater(
      ImgBbUploader.upload(image([1])),
      throwsA(isA<ImgBbUploadException>().having(
        (e) => e.message,
        'message',
        'Image upload failed. Check your internet connection.',
      )),
    );
  });

  test('a missing API key never reaches the network', () async {
    dotenv.testLoad(mergeWith: {'IMGBB_API_KEY': ''});
    var called = false;
    ImgBbUploader.client = MockClient((request) async {
      called = true;
      return http.Response('{}', 200);
    });

    await expectLater(
      ImgBbUploader.upload(image([1])),
      throwsA(isA<ImgBbUploadException>()),
    );
    expect(called, isFalse);
  });
}

/// Thrown from the fake client to simulate a dead connection.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
