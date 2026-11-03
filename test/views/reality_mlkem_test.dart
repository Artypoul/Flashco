import 'package:flashco/providers/app.dart';
import 'package:flashco/state.dart';
import 'package:flashco/views/profiles/reality_mlkem.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

Future<void> openDialog(
  WidgetTester tester,
  Map<String, bool> saved,
  ValueChanged<RealityMlkemSelection?> onResult, {
  bool inheritedEnabled = true,
  bool? enabled,
}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final subscription = container.listen(viewSizeProvider, (_, _) {});
  addTearDown(subscription.close);
  container.read(viewSizeProvider.notifier).value = const Size(900, 800);
  globalState.container = container;
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: TestApp(
        locale: const Locale('en'),
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              onResult(
                await showDialog<RealityMlkemSelection>(
                  context: context,
                  builder: (_) => RealityMlkemDialog(
                    nodes: const [(key: 'node', name: 'Example')],
                    overrides: saved,
                    inheritedEnabled: inheritedEnabled,
                    enabled: enabled,
                  ),
                ),
              );
            },
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
  testWidgets('a profile can override a disabled common setting', (
    tester,
  ) async {
    RealityMlkemSelection? result;
    await openDialog(
      tester,
      {},
      (value) => result = value,
      inheritedEnabled: false,
    );
    expect(find.text('Inherit (Disabled)'), findsNWidgets(2));
    await tester.tap(find.text('Profile default'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enabled'));
    await tester.pumpAndSettle();
    expect(find.text('Inherit (Enabled)'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(result?.enabled, true);
    expect(result?.nodes, isEmpty);
  });

  testWidgets('a profile needs no saved choices to use the enabled default', (
    tester,
  ) async {
    RealityMlkemSelection? result;
    await openDialog(tester, {}, (value) => result = value);
    expect(find.text('Inherit (Enabled)'), findsNWidgets(2));
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(result?.nodes, isEmpty);
    expect(result?.enabled, isNull);
  });

  testWidgets('a node can use the default again and absent nodes stay saved', (
    tester,
  ) async {
    final saved = {'node': true, 'temporarily absent': false};
    RealityMlkemSelection? result;
    await openDialog(tester, saved, (value) => result = value);
    expect(find.text('Enabled'), findsOneWidget);
    await tester.tap(find.text('Example'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inherit (Enabled)').last);
    await tester.pumpAndSettle();
    expect(find.text('Inherit (Enabled)'), findsNWidgets(2));
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(result?.nodes, {'temporarily absent': false});
    expect(result?.enabled, isNull);
    expect(saved, {'node': true, 'temporarily absent': false});
  });

  testWidgets('cancel discards changes without altering the saved selection', (
    tester,
  ) async {
    final saved = {'node': true};
    RealityMlkemSelection? result;
    var returned = false;
    await openDialog(tester, saved, (value) {
      returned = true;
      result = value;
    });
    await tester.tap(find.text('Example'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disabled'));
    await tester.pumpAndSettle();
    expect(find.text('Disabled'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(returned, true);
    expect(result, isNull);
    expect(saved, {'node': true});
  });
}
