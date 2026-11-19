import 'dart:async';

import 'package:flashco/common/common.dart';
import 'package:flashco/models/models.dart';
import 'package:flashco/providers/action.dart';
import 'package:flashco/providers/app.dart';
import 'package:flashco/providers/config.dart';
import 'package:flashco/providers/database.dart';
import 'package:flashco/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

import '../helpers/preferences.dart';
import '../helpers/test_profiles.dart';

class RestoreCommonAction extends CommonAction {
  @override
  Future<void> updateTraffic() async {}
}

class RestoreAction extends SetupAction {
  Future<DateTime?> Function()? readStartTime;
  final appliedForce = <bool>[];
  final runningCalls = <bool>[];

  @override
  Future<DateTime?> serviceStartTime() async => readStartTime?.call();

  @override
  Future<bool> applyProfile({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
  }) async {
    appliedForce.add(force);
    return true;
  }

  @override
  Future<bool> setCoreRunning(bool running) async {
    runningCalls.add(running);
    return true;
  }

  @override
  void resetCoreTraffic() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RestoreAction action;
  late ProviderContainer container;

  setUp(() async {
    await mockPreferences({appliedConfigMd5Key: 'running'});
    action = RestoreAction();
    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(TestProfiles.new),
        setupActionProvider.overrideWith(() => action),
        commonActionProvider.overrideWith(RestoreCommonAction.new),
      ],
    );
    globalState.container = container;
    container.read(setupActionProvider.notifier);
    globalState.needInitStatus = true;
    globalState.lastConfigMd5 = null;
  });

  tearDown(() {
    container.dispose();
    globalState.needInitStatus = true;
    globalState.lastConfigMd5 = null;
  });

  test(
    'restores a running service digest and compares before applying',
    () async {
      action.readStartTime = () async =>
          DateTime.now().subtract(const Duration(minutes: 1));
      await action.initStatus();
      expect(globalState.lastConfigMd5, 'running');
      expect(action.appliedForce, [false]);
      expect(action.runningCalls, [true]);
    },
  );

  test(
    'does not trust a saved digest when starting a stopped service',
    () async {
      container.read(appSettingProvider.notifier).value = const AppSettingProps(
        autoRun: true,
      );
      await action.initStatus();
      expect(globalState.lastConfigMd5, isNull);
      expect(action.appliedForce, [true]);
    },
  );

  test(
    'a stop while reading the service state wins over restoration',
    () async {
      final start = Completer<DateTime?>();
      action.readStartTime = () => start.future;
      final initializing = action.initStatus();
      await action.setRunning(false);
      start.complete(DateTime.now().subtract(const Duration(minutes: 1)));
      await initializing;
      expect(action.runningCalls, [false]);
      expect(container.read(runTimeProvider), isNull);
      expect(action.appliedForce, isEmpty);
    },
  );
}
