import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/entities/mind_item.dart';

/// "Export my data" — a portable JSON backup of every saved item.
class DataExport {
  DataExport._();

  static String buildJson(List<MindItem> items, {DateTime? now}) {
    final payload = {
      'app': 'KeepIt',
      'format': 'keepit-export',
      'version': 1,
      'exportedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'count': items.length,
      'items': items.map((i) => i.toMap()..remove('isSynced')).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Writes the export to a temp file and opens the system share sheet.
  static Future<ShareResultStatus> shareExport(List<MindItem> items) async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final file = File('${dir.path}/keepit-export-$stamp.json');
    await file.writeAsString(buildJson(items), flush: true);
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: 'KeepIt export ($stamp)',
        text: 'My KeepIt data export — ${items.length} items.',
      ),
    );
    return result.status;
  }
}
