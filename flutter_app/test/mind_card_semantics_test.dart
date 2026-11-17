import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/theme/app_theme.dart';
import 'package:keepit/domain/entities/mind_item.dart';
import 'package:keepit/presentation/widgets/mind_card_widget.dart';
import 'package:flutter/semantics.dart';
import 'package:material_ui/material_ui.dart';

/// Accessibility guard: a card is a button. Before this, TalkBack announced the
/// title text but nothing told the user the card could be opened or long-pressed
/// (Play's accessibility scan flags exactly that).
void main() {
  MindItem item({String? author, bool watched = false, bool top = false}) {
    final t = DateTime.utc(2026, 9, 1, 12);
    return MindItem(
      id: 'c1',
      title: 'A very useful reel',
      url: 'https://www.instagram.com/reel/abc',
      authorName: author,
      type: ItemType.instagramReel,
      isWatched: watched,
      isTopMind: top,
      createdAt: t,
      updatedAt: t,
    );
  }

  Future<void> pumpCard(
    WidgetTester tester,
    MindItem card, {
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    return tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                child: MindCardWidget(
                  item: card,
                  onTap: onTap ?? () {},
                  onLongPress: onLongPress ?? () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a card is announced as a button with a readable label',
      (tester) async {
    final handle = tester.ensureSemantics();
    var tapped = 0;
    await pumpCard(tester, item(author: 'Keshab'), onTap: () => tapped++);

    // MindCardWidget is a ConsumerWidget (no render object of its own), so
    // locate the semantics node by its label instead of by type.
    final node = tester.getSemantics(
      find.bySemanticsLabel(RegExp('A very useful reel')),
    );
    expect(node.label, contains('A very useful reel'));
    expect(node.label, contains('Keshab'));
    expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
    expect(
      node.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
      reason: 'a screen reader must offer "double tap to activate"',
    );
    expect(
        node.getSemanticsData().hasAction(SemanticsAction.longPress), isTrue);

    // The action really reaches the widget's callback.
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.tap,
        nodeId: node.id,
        viewId: tester.view.viewId,
      ),
    );
    await tester.pump();
    expect(tapped, 1);

    handle.dispose();
  });

  testWidgets('seen and top-of-mind state are spoken, URL only falls back',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpCard(tester, item(watched: true, top: true));

    // MindCardWidget is a ConsumerWidget (no render object of its own), so
    // locate the semantics node by its label instead of by type.
    final node = tester.getSemantics(
      find.bySemanticsLabel(RegExp('A very useful reel')),
    );
    expect(node.label, contains('Already seen'));
    expect(node.label, contains('Top of mind'));
    // No author: the host stands in, so the user still knows the source.
    expect(node.label, contains('instagram.com'));
    handle.dispose();
  });
}
