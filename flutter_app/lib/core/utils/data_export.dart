import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/entities/custom_space.dart';
import '../../domain/entities/mind_item.dart';

/// "Export my data" — a portable JSON backup of every saved item.
class DataExport {
  DataExport._();

  /// 1: items only. 2: items + the user's Spaces.
  ///
  /// A v1 file still imports (its items just arrive without their Spaces, as
  /// they always did); the marker only exists so the reader can tell the two
  /// apart without guessing.
  static const int formatVersion = 2;

  static String buildJson(
    List<MindItem> items, {
    List<CustomSpace> spaces = const [],
    DateTime? now,
  }) {
    final payload = {
      'app': 'KeepIt',
      'format': 'keepit-export',
      'version': formatVersion,
      'exportedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'count': items.length,
      'items': items.map((i) => i.toMap()..remove('isSynced')).toList(),
      // Spaces are part of the library, not decoration: restoring items without
      // them left every card pointing at a Space that did not exist any more.
      'spaceCount': spaces.length,
      'spaces': spaces.map((s) => s.toMap()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Writes the export to a temp file and opens the system share sheet.
  static Future<ShareResultStatus> shareExport(
    List<MindItem> items, {
    List<CustomSpace> spaces = const [],
  }) async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final file = File('${dir.path}/keepit-export-$stamp.json');
    await file.writeAsString(
      buildJson(items, spaces: spaces),
      flush: true,
    );
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: 'KeepIt export ($stamp)',
        text: 'My KeepIt data export — ${items.length} items, '
            '${spaces.length} spaces.',
      ),
    );
    return result.status;
  }
}
