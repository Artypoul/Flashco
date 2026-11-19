import 'dart:async';
import 'dart:convert';

import 'package:flashco/common/common.dart';
import 'package:flashco/manager/android_manager.dart';
import 'package:flashco/models/models.dart';
import 'package:flashco/plugins/service.dart';
import 'package:flashco/providers/action.dart';
import 'package:flashco/providers/config.dart';
import 'package:flashco/providers/database.dart';
import 'package:flashco/providers/state.dart';
import 'package:flashco/state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../helpers/preferences.dart';
import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

class _RecordingPreferencesStore extends InMemorySharedPreferencesStore {
  _RecordingPreferencesStore() : super.empty();

  final sharedStateWritten = Completer<void>();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    final result = await super.setValue(valueType, key, value);
    if (key == 'flutter.sharedState' && !sharedStateWritten.isCompleted) {
      sharedStateWritten.complete();
    }
    return result;
  }
}

class _RecordingSetupAction extends SetupAction {
  static final requests = <bool>[];

  @override
  Future<bool> setRunning(bool running, {bool initialize = false}) async {
    requests.add(running);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late SharedPreferences store;
  late _RecordingPreferencesStore platformStore;

  setUp(() async {
    await mockPreferences();
    store = await SharedPreferences.getInstance();
    platformStore = _RecordingPreferencesStore();
    SharedPreferencesStorePlatform.instance = platformStore;
    _RecordingSetupAction.requests.clear();
    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(TestProfiles.new),
        setupActionProvider.overrideWith(_RecordingSetupAction.new),
        // Bypassing private addresses computes the routes in Isolate.run, which
        // the fake clock never lets finish.
        networkSettingProvider.overrideWithBuild(
          (_, _) => const NetworkProps(bypassPrivateRoute: false),
        ),
      ],
    );
    globalState.container = container;
  });

  tearDown(() => container.dispose());

  Future<void> pumpAndroidManager(WidgetTester tester) async {
    await container.read(vpnOptionsProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(
          child: AndroidManager(child: SizedBox(key: Key('child'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders its child unchanged', (tester) async {
    await pumpAndroidManager(tester);

    expect(find.byKey(const Key('child')), findsOneWidget);
    expect(tester.takeException(), null);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a stop the service reports turns the running state off', (
    tester,
  ) async {
    await pumpAndroidManager(tester);
    final listener =
        tester.state(find.byType(AndroidManager)) as ServiceListener;

    listener.onServiceStopped();
    await tester.pump();

    expect(_RecordingSetupAction.requests, [false]);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('persists shared state after the debounce window', (
    tester,
  ) async {
    // The debounce runs in the widget test's fake-async zone.
    final originalPreferences = preferences.sharedPreferencesCompleter;
    addTearDown(
      () => preferences.sharedPreferencesCompleter = originalPreferences,
    );
    preferences.sharedPreferencesCompleter = Completer<SharedPreferences?>()
      ..complete(store);
    await pumpAndroidManager(tester);
    expect(store.getString('sharedState'), isNull);

    final changes = <SharedState>[];
    final subscription = container.listen(
      sharedStateProvider,
      (_, next) => changes.add(next),
    );
    addTearDown(subscription.close);
    container.read(patchClashConfigProvider.notifier).value =
        const PatchClashConfig(testUrl: 'http://shared.test');
    await tester.pump();
    expect(
      container.read(sharedStateProvider).setupParams?.options.testUrl,
      'http://shared.test',
    );
    await tester.pump();
    expect(changes.last.setupParams?.options.testUrl, 'http://shared.test');
    await tester.pump(const Duration(milliseconds: 999));
    expect(platformStore.sharedStateWritten.isCompleted, isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(platformStore.sharedStateWritten.isCompleted, isTrue);

    final raw = store.getString('sharedState');
    expect(raw, isNotNull);
    final restored = SharedState.fromJson(
      json.decode(raw!) as Map<String, Object?>,
    );
    expect(restored.setupParams?.options.testUrl, 'http://shared.test');
    expect(tester.takeException(), null);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('does not persist when shared state is unchanged', (
    tester,
  ) async {
    await pumpAndroidManager(tester);

    container.read(appSettingProvider.notifier).value = const AppSettingProps();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(store.getString('sharedState'), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
