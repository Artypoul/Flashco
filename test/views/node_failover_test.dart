import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flashco/common/common.dart';
import 'package:flashco/enum/enum.dart';
import 'package:flashco/models/models.dart';
import 'package:flashco/providers/providers.dart';
import 'package:flashco/state.dart';
import 'package:flashco/views/proxies/card.dart';
import 'package:flashco/widgets/widgets.dart';
import 'package:flashco/views/proxies/safe.dart';
import 'package:flashco/views/proxies/tab.dart';
import 'package:flashco/views/proxies/list.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';
import '../common/safe_mode_test.dart' show fixture;

class RecordingSetup extends SetupAction {
  final forces = <bool>[];
  @override
  Future<bool> applyProfile({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
  }) async {
    forces.add(force);
    return true;
  }
}

void main() {
  setUpAll(() async {
    if (const String.fromEnvironment('SAFE_SCREENSHOT_DIR').isNotEmpty) {
      final loader = FontLoader('Roboto')
        ..addFont(
          File(
            'C:/Windows/Fonts/segoeui.ttf',
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      await loader.load();
      final emoji = FontLoader('Twemoji')
        ..addFont(rootBundle.load('assets/fonts/Twemoji.Mozilla.ttf'));
      await emoji.load();
    }
  });
  for (final width in [390.0, 1100.0]) {
    testWidgets(
      'Safe follows Fastest and saves both roles immediately at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final config = fixture();
        for (final proxy in (config['proxies'] as List).cast<Map>()) {
          proxy['name'] = '🇳🇱 Нидерланды | ${proxy['network']}';
        }
        final profile = Profile.normal().copyWith(currentGroupName: 'Safe');
        final setup = RecordingSetup();
        final container = ProviderContainer(
          overrides: [
            currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
            profilesProvider.overrideWith(() => TestProfiles([profile])),
            safeProfileConfigProvider.overrideWith((_) async => config),
            setupActionProvider.overrideWith(() => setup),
          ],
        );
        globalState.container = container;
        final hold = container.listen(currentProfileProvider, (_, _) {});
        container.read(viewSizeProvider.notifier).value = Size(width, 850);
        container.read(groupsProvider.notifier).value = [
          for (final (name, type) in [
            ('PROXY', GroupType.Selector),
            ('Fastest', GroupType.URLTest),
          ])
            Group(
              name: name,
              type: type,
              hidden: false,
              all: [
                for (final node in safeProfileNodes(config))
                  Proxy(name: node.name, type: 'Vless'),
              ],
            ),
        ];
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const TestApp(
              locale: Locale('en'),
              child: Scaffold(body: ProxiesTabView()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          container.read(proxiesTabStateProvider).groups.map((g) => g.name),
          ['PROXY', 'Fastest', 'Safe'],
        );
        expect(find.text('Tap a node to use Safe'), findsOneWidget);
        expect(find.byType(Switch), findsNothing);
        final primary = find.byWidgetPredicate(
          (w) =>
              w is ProxyCard &&
              w.groupName == 'Safe' &&
              w.proxy.name.endsWith('xhttp'),
        );
        await tester.tap(primary);
        await tester.pumpAndSettle();
        expect(
          container
              .read(currentProfileProvider)!
              .overrides
              .nodeFailover!
              .enabled,
          true,
        );
        await tester.tap(find.byType(ChoiceChip).last);
        await tester.pumpAndSettle();
        final reserve = find.byWidgetPredicate(
          (w) =>
              w is ProxyCard &&
              w.groupName == 'Safe' &&
              w.proxy.name.endsWith('grpc'),
        );
        await tester.tap(reserve);
        await tester.pumpAndSettle();
        final saved = container
            .read(currentProfileProvider)!
            .overrides
            .nodeFailover!;
        final nodes = safeProfileNodes(config);
        expect(saved.primaryKey, nodes[0].key);
        expect(saved.backupKey, nodes[1].key);
        expect(container.read(selectedMapProvider)['PROXY'], 'Safe');
        expect(setup.forces, [true, true]);
        container.read(groupsProvider.notifier).value = [
          ...container.read(groupsProvider),
          Group(
            name: 'Safe',
            type: GroupType.Fallback,
            hidden: false,
            now: nodes[1].name,
            all: [
              for (final node in nodes) Proxy(name: node.name, type: 'Vless'),
            ],
          ),
        ];
        await tester.tap(find.byType(ChoiceChip).first);
        await tester.pumpAndSettle();
        expect(find.byType(SelectIcon), findsOneWidget);
        expect(tester.takeException(), isNull);
        const screenshotDir = String.fromEnvironment('SAFE_SCREENSHOT_DIR');
        if (screenshotDir.isNotEmpty) {
          final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
            find.byType(RepaintBoundary),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            await Directory(screenshotDir).create(recursive: true);
            await File(
              '$screenshotDir/safe-$width.png',
            ).writeAsBytes(bytes.buffer.asUint8List());
            image.dispose();
          });
        }
        // The list layout uses the same controls and role-specific card callback.
        container
            .read(profilesProvider.notifier)
            .put(
              container
                  .read(currentProfileProvider)!
                  .copyWith(unfoldSet: {'Safe'}),
            );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const TestApp(
              locale: Locale('en'),
              child: Scaffold(body: ProxiesListView()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SafeControls), findsOneWidget);
        expect(find.byType(SafeNodeCard), findsNWidgets(3));
        await tester.pumpWidget(const SizedBox());
        hold.close();
        container.dispose();
      },
    );
  }
  testWidgets('Safe shows an actionable empty state without an off switch', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [safeProfileConfigProvider.overrideWith((_) async => {})],
    );
    globalState.container = container;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          locale: const Locale('en'),
          child: Scaffold(body: SafeControls(backup: false, onChanged: (_) {})),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('No supported nodes'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });
  testWidgets('failed node loading offers retry and never edits the profile', (
    tester,
  ) async {
    var attempts = 0;
    final profile = Profile.normal();
    final container = ProviderContainer(
      overrides: [
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        safeProfileConfigProvider.overrideWith((_) async {
          if (++attempts == 1) throw StateError('fixture unavailable');
          return fixture();
        }),
      ],
    );
    globalState.container = container;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          locale: const Locale('en'),
          child: Scaffold(body: SafeControls(backup: false, onChanged: (_) {})),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byType(ChoiceChip), findsNWidgets(2));
    expect(
      container.read(currentProfileProvider)!.overrides.nodeFailover,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });
}
