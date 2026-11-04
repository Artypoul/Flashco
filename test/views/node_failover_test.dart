import 'package:flashco/common/common.dart';
import 'package:flashco/models/models.dart';
import 'package:flashco/providers/app.dart';
import 'package:flashco/state.dart';
import 'package:flashco/views/profiles/node_failover.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

const saved = ProfileNodeFailover(
  groupName: 'My route',
  primaryKey: 'a',
  backupKey: 'b',
  primaryName: 'Primary',
  backupName: 'Backup',
);
const nodes = <ProfileFailoverNode>[
  (key: 'a', name: 'Primary', definition: {}),
  (key: 'b', name: 'Backup', definition: {}),
];

Future<void> openPair(
  WidgetTester tester,
  ValueChanged<NodeFailoverSelection?> done, {
  ProfileNodeFailover? initial,
  List<ProfileFailoverNode> available = nodes,
}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final hold = container.listen(viewSizeProvider, (_, _) {});
  addTearDown(hold.close);
  container.read(viewSizeProvider.notifier).value = const Size(900, 1000);
  globalState.container = container;
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: TestApp(
        locale: const Locale('en'),
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () async => done(
              await showDialog<NodeFailoverSelection>(
                context: context,
                builder: (_) => NodeFailoverDialog(
                  nodes: available,
                  groups: const ['My route'],
                  initial: initial,
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String field, String value) async {
  await tester.tap(find.byKey(ValueKey(field)).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('chooses and saves a distinct primary and backup', (
    tester,
  ) async {
    NodeFailoverSelection? result;
    await openPair(tester, (value) => result = value);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm'))
          .onPressed,
      isNull,
    );
    await choose(tester, 'failover-primary', 'Primary');
    await choose(tester, 'failover-backup', 'Primary');
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm'))
          .onPressed,
      isNull,
    );
    await choose(tester, 'failover-primary', 'Backup');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(
      result?.pair,
      saved.copyWith(
        primaryKey: 'b',
        backupKey: 'a',
        primaryName: 'Backup',
        backupName: 'Primary',
      ),
    );
  });

  testWidgets(
    'missing saved nodes remain visible and cancel preserves settings',
    (tester) async {
      NodeFailoverSelection? result;
      await openPair(
        tester,
        (value) => result = value,
        initial: saved,
        available: const [],
      );
      expect(find.textContaining('Primary · Missing'), findsOneWidget);
      expect(find.textContaining('Backup · Missing'), findsOneWidget);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(result?.pair, saved);
      result = null;
      await openPair(tester, (value) => result = value, initial: saved);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    },
  );

  testWidgets('a saved pair can be disabled or removed', (tester) async {
    NodeFailoverSelection? result;
    await openPair(tester, (value) => result = value, initial: saved);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(result?.pair, saved.copyWith(enabled: false));
    await openPair(tester, (value) => result = value, initial: saved);
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(result, (pair: null));
  });

  testWidgets('a newly chosen pair is retained when saved disabled', (
    tester,
  ) async {
    NodeFailoverSelection? result;
    await openPair(tester, (value) => result = value);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await choose(tester, 'failover-primary', 'Primary');
    await choose(tester, 'failover-backup', 'Backup');
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(result?.pair, saved.copyWith(enabled: false));
  });
}
