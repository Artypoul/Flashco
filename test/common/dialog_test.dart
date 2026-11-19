import 'package:flashco/common/common.dart';
import 'package:flashco/ui/icons/icons.dart';
import 'package:flashco/l10n/l10n.dart';
import 'package:flashco/models/models.dart';
import 'package:flashco/providers/app.dart';
import 'package:flashco/state.dart';
import 'package:flashco/views/disclaimer.dart';
import 'package:flashco/ui/ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/glyph_finders.dart';
import '../helpers/test_app.dart';
import '../helpers/host_scaffold.dart';

Future<ProviderContainer> _pumpHost(
  WidgetTester tester, {
  Widget Function(Widget child)? homeBuilder,
  Size size = const Size(1000, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer();
  addTearDown(container.dispose);
  globalState.container = container;
  container.read(viewSizeProvider.notifier).update((_) => size);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: TestApp(
        homeBuilder: homeBuilder ?? (child) => child,
        child: const HostScaffold(body: SizedBox.shrink()),
      ),
    ),
  );
  await tester.pump();
  return container;
}

FilledButton _disclaimerAgreeButton(WidgetTester tester) {
  return tester.widget<FilledButton>(
    find.descendant(
      of: find.byType(DisclaimerView),
      matching: find.byType(FilledButton),
    ),
  );
}

Future<void> _agree(WidgetTester tester) async {
  await tester.tap(find.text('Agree'));
  await tester.pumpAndSettle();
}

/// [PrismApp] mounts the [BannerHost] above its navigator, so
/// [Dialogs.showBanner] can reach it from `navigatorKey.currentContext`.
Future<void> _pumpBannerHost(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer();
  addTearDown(container.dispose);
  globalState.container = container;
  container
      .read(viewSizeProvider.notifier)
      .update((_) => const Size(1000, 800));

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: PrismApp(
        navigatorKey: globalState.navigatorKey,
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        builder: (context, child) {
          globalState.measure = MeasureScope.of(context);
          return child!;
        },
        home: const HostScaffold(body: SizedBox.shrink()),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('subscription input validates HTTP(S) before submission', (
    tester,
  ) async {
    await _pumpHost(tester);
    final result = dialogs.showSubscriptionUrlInput();
    await tester.pumpAndSettle();

    for (final value in [
      '',
      'ftp://example.invalid/subscription',
      'https://example.invalid/a b',
    ]) {
      await tester.enterText(find.byType(TextFormField), value);
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();

      expect(find.byType(TextFormField), findsOneWidget);
      final localizations = currentAppLocalizations;
      expect(
        find.text(
          value.isEmpty
              ? localizations.emptyTip(localizations.value)
              : localizations.urlTip(localizations.value),
        ),
        findsOneWidget,
      );
    }

    const url = '  https://example.invalid/subscription  ';
    await tester.enterText(find.byType(TextFormField), url);
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(await result, url);
    expect(tester.takeException(), isNull);
  });

  testWidgets('subscription retry retains the URL and can be cancelled', (
    tester,
  ) async {
    await _pumpHost(tester);
    const url = 'https://example.invalid/subscription';
    final result = dialogs.showSubscriptionUrlInput(value: url);
    await tester.pumpAndSettle();

    expect(find.text(url), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await result, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('showMessage resolves true when confirmed', (tester) async {
    await _pumpHost(tester);

    final result = dialogs.showMessage(message: const TextSpan(text: 'body'));
    await tester.pumpAndSettle();

    expect(find.text('body'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(await result, isTrue);
    expect(tester.takeException(), null);
  });

  testWidgets('showMessage resolves false when cancelled', (tester) async {
    await _pumpHost(tester);

    final result = dialogs.showMessage(message: const TextSpan(text: 'body'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await result, isFalse);
  });

  testWidgets('showMessage hides the cancel action when not cancelable', (
    tester,
  ) async {
    await _pumpHost(tester);

    final result = dialogs.showMessage(
      message: const TextSpan(text: 'body'),
      cancelable: false,
    );
    await tester.pumpAndSettle();

    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Confirm'), findsOneWidget);

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });

  testWidgets('showMessage honours custom title and action labels', (
    tester,
  ) async {
    await _pumpHost(tester);

    final result = dialogs.showMessage(
      message: const TextSpan(text: 'body'),
      title: 'Custom title',
      confirmText: 'Go',
      cancelText: 'Back',
    );
    await tester.pumpAndSettle();

    expect(find.text('Custom title'), findsOneWidget);
    expect(find.text('Go'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });

  testWidgets('showCommonDialog returns the value the child pops', (
    tester,
  ) async {
    await _pumpHost(tester);

    final result = dialogs.showCommonDialog<String>(
      child: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).pop('picked'),
          child: const Text('pick'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();

    expect(await result, 'picked');
  });

  testWidgets('a dialog stacked on a dialog brings its own scrim', (
    tester,
  ) async {
    await _pumpHost(tester);

    final result = dialogs.showCommonDialog<void>(
      child: Builder(
        builder: (context) => TextButton(
          onPressed: () {
            dialogs.showCommonDialog<void>(
              context: context,
              child: const Text('inner'),
            );
          },
          child: const Text('open inner'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final outer = tester.element(find.text('open inner'));
    final scrim = outer.colorScheme.alertScrim;
    expect(ModalRoute.of(outer)!.barrierColor, scrim);

    await tester.tap(find.text('open inner'));
    await tester.pumpAndSettle();
    final inner = tester.element(find.text('inner'));
    expect(ModalRoute.of(inner)!.barrierColor, scrim);
    expect(find.byType(BackdropFilter), findsNothing);

    Navigator.of(inner).pop();
    await tester.pumpAndSettle();
    Navigator.of(outer).pop();
    await tester.pumpAndSettle();
    await result;
  });

  testWidgets('showFailureDetails groups failures under their reason', (
    tester,
  ) async {
    await _pumpHost(tester);

    const longMessage =
        'failed to update provider because the Go core returned a very long '
        'error message that cannot fit on a single line';
    final result = dialogs.showFailureDetails(const [
      UpdatingMessage(label: 'profile-a', message: 'updated'),
      UpdatingMessage(label: 'profile-b', message: longMessage),
      UpdatingMessage(label: 'profile-c', message: longMessage),
    ]);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Error details'), findsOneWidget);
    expect(find.text('profile-a'), findsOneWidget);
    expect(find.text('profile-b'), findsOneWidget);
    expect(find.text('profile-c'), findsOneWidget);
    final messageText = tester.widget<Text>(find.text(longMessage));
    expect(messageText.maxLines, isNull);
    expect(
      tester.getTopLeft(find.text('profile-c')).dy,
      lessThan(tester.getTopLeft(find.text(longMessage)).dy),
    );
    expect(find.byGlyph(AppGlyphs.error), findsNothing);

    Navigator.of(tester.element(find.text('profile-a'))).pop();
    await tester.pumpAndSettle();
    await result;
    expect(find.text('profile-a'), findsNothing);
  });

  testWidgets('requestDisclaimerConsent maps agree and back to a boolean', (
    tester,
  ) async {
    await _pumpHost(tester);

    final agreed = requestDisclaimerConsent();
    await tester.pumpAndSettle();
    expect(find.text('Data collection and privacy'), findsOneWidget);
    await _agree(tester);
    expect(await agreed, isTrue);

    final dismissed = requestDisclaimerConsent();
    await tester.pumpAndSettle();
    rootNavigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(await dismissed, isFalse);
  });

  for (final size in [const Size(1000, 800), const Size(400, 800)]) {
    testWidgets(
      'consent takes one click without scrolling or typing at $size',
      (tester) async {
        await _pumpHost(tester, size: size);
        final agreed = requestDisclaimerConsent();
        await tester.pumpAndSettle();

        expect(_disclaimerAgreeButton(tester).onPressed, isNotNull);
        await _agree(tester);

        expect(find.byType(TextField), findsNothing);
        expect(find.byType(DisclaimerView), findsNothing);
        expect(await agreed, isTrue);
      },
    );
  }
  testWidgets(
    'disclaimer consent on desktop keeps the title clear of the window corner',
    (tester) async {
      await _pumpHost(tester);

      final agreed = requestDisclaimerConsent();
      await tester.pumpAndSettle();

      final view = find.byType(DisclaimerView);
      expect(
        find.descendant(of: view, matching: find.byType(AppBar)),
        findsNothing,
        reason:
            'the macOS traffic lights sit over the top-left corner, where an '
            'app bar puts its back button, and backing out declines anyway',
      );
      expect(
        tester
            .getTopLeft(
              find.descendant(of: view, matching: find.text('Disclaimer')),
            )
            .dy,
        greaterThanOrEqualTo(macOSTrafficLightsArea.height),
      );
      expect(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.text('Agree'),
        ),
        findsOneWidget,
      );

      rootNavigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(await agreed, isFalse);
    },
  );

  testWidgets('DisclaimerView without consent shows no agree or exit', (
    tester,
  ) async {
    await _pumpHost(tester, homeBuilder: (_) => const DisclaimerView());

    expect(find.text('Disclaimer'), findsWidgets);
    expect(find.textContaining('Created for fun.'), findsOneWidget);
    expect(find.textContaining('Clash.Meta'), findsNothing);
    expect(find.text('Agree'), findsNothing);
    expect(find.text('Exit'), findsNothing);
  });

  testWidgets('showBanner delivers text through the banner host', (
    tester,
  ) async {
    await _pumpBannerHost(tester);

    dialogs.showBanner('something happened');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('something happened'), findsOneWidget);
    expect(tester.takeException(), null);
  });

  testWidgets('showBanner drops empty text', (tester) async {
    await _pumpBannerHost(tester);

    dialogs.showBanner('');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(''), findsNothing);
    expect(tester.takeException(), null);
  });

  testWidgets('showBanner is inert without a banner host', (tester) async {
    await tester.pumpWidget(
      WidgetsApp(
        navigatorKey: globalState.navigatorKey,
        color: const Color(0xFF000000),
        onGenerateRoute: (settings) => CardPageRoute<void>(
          settings: settings,
          builder: (_) => const SizedBox.shrink(),
        ),
      ),
    );

    dialogs.showBanner('no host listening');
    await tester.pumpAndSettle();

    expect(find.text('no host listening'), findsNothing);
    expect(tester.takeException(), null);
  });
}
