import 'package:flashco/models/models.dart';
import 'package:flashco/providers/app.dart';
import 'package:flashco/state.dart';
import 'package:flashco/views/config/connection_recovery.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

Future<void> open(
  WidgetTester tester,
  ValueChanged<ConnectionRecoveryChoice?> done,
) async {
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
              await showDialog<ConnectionRecoveryChoice>(
                context: context,
                builder: (_) => const ConnectionRecoveryDialog(
                  initial: (reconnect: null, failover: null, interval: null),
                  global: PatchClashConfig(),
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

void main() {
  testWidgets('a profile saves a disabled override and a custom interval', (
    tester,
  ) async {
    ConnectionRecoveryChoice? result;
    await open(tester, (value) => result = value);
    expect(find.text('Inherit (Enabled)'), findsNWidgets(2));
    await tester.tap(find.text('Reconnect after disconnect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disabled'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '23');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(result, (reconnect: false, failover: null, interval: 23));
  });

  testWidgets('invalid intervals cannot be saved and cancel discards changes', (
    tester,
  ) async {
    ConnectionRecoveryChoice? result;
    await open(tester, (value) => result = value);
    await tester.enterText(find.byType(TextFormField), '0');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a number from 1 to 3600'), findsOneWidget);
    expect(result, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
