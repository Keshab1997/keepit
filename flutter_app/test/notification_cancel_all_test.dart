import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/notifications/serendipity_store.dart';
import 'package:keepit/core/utils/notification_service.dart';
import 'package:keepit/domain/entities/mind_item.dart';

/// `cancelAll()` is what runs when the user signs out or deletes the account.
/// It must leave nothing scheduled and must persist that empty plan, otherwise
/// the old account's titles stay in the notification tray (and a tap opens an
/// item that no longer exists).
void main() {
  MindItem savedLongAgo(String id) {
    final t = DateTime.now().toUtc().subtract(const Duration(days: 400));
    return MindItem(
      id: id,
      title: 'Saved before signing out',
      type: ItemType.webArticle,
      createdAt: t,
      updatedAt: t,
    );
  }

  test('after cancelAll nothing is planned and the state file agrees',
      () async {
    final store = SerendipityStore.inMemory();
    final service = NotificationService();
    await service.initHeadless(store: store);

    await service.reschedule([savedLongAgo('a')]);
    expect(service.upcoming, isNotEmpty);

    await service.cancelAll();

    expect(service.upcoming, isEmpty);
    // Persisted, so a cold start (or the background isolate) sees no plan.
    expect((await store.loadState()).plan, isEmpty);
  });

  test('planning again after a wipe schedules nothing', () async {
    final store = SerendipityStore.inMemory();
    final service = NotificationService();
    await service.initHeadless(store: store);
    await service.reschedule([savedLongAgo('a')]);
    await service.cancelAll();

    // This is what NotificationHost does after sign-out: re-plan from whatever
    // items remain locally. After "delete local data" that list is empty.
    await service.reschedule(const []);
    expect(service.upcoming, isEmpty);

    // And the reminder stage bookkeeping did not resurrect the old item.
    expect((await store.loadState()).lastStage.containsKey('a'), isFalse);
  });
}
