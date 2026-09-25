import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'serendipity_planner.dart';

/// Something the user did from a notification's action buttons, possibly
/// while the app was closed (handled in a background isolate).
class NotificationActionRecord {
  static const String watched = 'watched';
  static const String snooze = 'snooze';

  final String type;
  final String itemId;

  /// Snooze only: the item stays silent until this moment.
  final DateTime? until;
  final DateTime at;

  const NotificationActionRecord({
    required this.type,
    required this.itemId,
    this.until,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'itemId': itemId,
        if (until != null) 'until': until!.toIso8601String(),
        'at': at.toIso8601String(),
      };

  static NotificationActionRecord? tryParse(String line) {
    try {
      final json = jsonDecode(line) as Map<String, dynamic>;
      return NotificationActionRecord(
        type: json['type'] as String,
        itemId: json['itemId'] as String,
        until: json['until'] == null
            ? null
            : DateTime.parse(json['until'] as String),
        at: DateTime.parse(json['at'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

/// File-based persistence for the Serendipity engine.
///
/// Plain JSON files (instead of Hive) are used on purpose: notification action
/// buttons run in a *separate background isolate*, and Hive boxes must not be
/// opened from two isolates at once. The background isolate only ever:
///   * reads `serendipity_state.json` (to know settings + what is scheduled)
///   * appends one line to `serendipity_actions.jsonl`
/// while the main isolate owns writing the state file and draining the queue.
class SerendipityStore {
  static const String stateFileName = 'serendipity_state.json';
  static const String queueFileName = 'serendipity_actions.jsonl';

  /// `null` means in-memory only (used by widget tests / unsupported platforms).
  final String? directoryPath;
  SerendipityEngineState _memoryState = const SerendipityEngineState();
  final List<NotificationActionRecord> _memoryQueue = [];

  SerendipityStore(this.directoryPath);

  SerendipityStore.inMemory() : directoryPath = null;

  static Future<SerendipityStore> open() async {
    try {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      return SerendipityStore(dir.path);
    } catch (_) {
      return SerendipityStore.inMemory();
    }
  }

  File? get _stateFile =>
      directoryPath == null ? null : File('$directoryPath/$stateFileName');
  File? get _queueFile =>
      directoryPath == null ? null : File('$directoryPath/$queueFileName');

  Future<SerendipityEngineState> loadState() async {
    final file = _stateFile;
    if (file == null) return _memoryState;
    try {
      if (!await file.exists()) return const SerendipityEngineState();
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return const SerendipityEngineState();
      return SerendipityEngineState.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      // Corrupt file: start fresh rather than crash the app.
      return const SerendipityEngineState();
    }
  }

  Future<void> saveState(SerendipityEngineState state) async {
    final file = _stateFile;
    if (file == null) {
      _memoryState = state;
      return;
    }
    // Write-then-rename so a reader never sees a half-written file.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(state.toJson()), flush: true);
    await tmp.rename(file.path);
  }

  Future<void> appendAction(NotificationActionRecord record) async {
    final file = _queueFile;
    if (file == null) {
      _memoryQueue.add(record);
      return;
    }
    await file.writeAsString(
      '${jsonEncode(record.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  /// Returns and removes all queued actions (oldest first).
  Future<List<NotificationActionRecord>> drainActions() async {
    final file = _queueFile;
    if (file == null) {
      final copy = List<NotificationActionRecord>.from(_memoryQueue);
      _memoryQueue.clear();
      return copy;
    }
    if (!await file.exists()) return const [];

    // Atomically move the queue aside so a concurrent append from the
    // background isolate lands in a fresh file instead of being lost.
    final processing = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.processing',
    );
    try {
      await file.rename(processing.path);
    } catch (_) {
      return const [];
    }
    try {
      final lines = await processing.readAsLines();
      return lines
          .where((l) => l.trim().isNotEmpty)
          .map(NotificationActionRecord.tryParse)
          .whereType<NotificationActionRecord>()
          .toList();
    } finally {
      try {
        await processing.delete();
      } catch (_) {}
    }
  }
}
