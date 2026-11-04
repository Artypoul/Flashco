import 'dart:async';
import 'package:flashco/common/common.dart';
import 'package:flashco/enum/enum.dart';
import 'package:drift/native.dart';
import 'package:flashco/database/database.dart' as db;
import 'package:flashco/models/models.dart';
import 'package:flashco/l10n/l10n.dart';
import 'package:flashco/providers/providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_profiles.dart';

const pair = ProfileNodeFailover(
  groupName: 'Safe',
  routeGroupName: 'My route',
  primaryKey: 'a',
  backupKey: 'b',
  primaryName: 'Primary',
  backupName: 'Backup',
);

class WaitingSetup extends SetupAction {
  final applied = Completer<bool>();
  bool entered = false;
  @override
  Future<bool> applyProfile({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
  }) {
    entered = true;
    return applied.future;
  }
}

class RecordingRebuildSetup extends SetupAction {
  final rebuilds = <({Mode mode, bool force})>[];
  @override
  void applyProfileDebounce({bool silence = false, bool force = false}) {
    rebuilds.add((mode: ref.read(patchClashConfigProvider).mode, force: force));
  }
}

void main() {
  test(
    'Android quick setup receives the effective automatic pair selection',
    () async {
      await AppLocalizations.load(const Locale('en'));
      final profile = Profile.normal().copyWith(
        selectedMap: const {'My route': 'Backup', 'GLOBAL': 'Third node'},
        overrides: const ProfileOverrides(nodeFailover: pair),
      );
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
          profilesProvider.overrideWith(() => TestProfiles([profile])),
          vpnRouteAddressProvider.overrideWith((_) async => const []),
        ],
      );
      addTearDown(container.dispose);
      final hold = container.listen(sharedStateProvider, (_, _) {});
      addTearDown(hold.close);
      expect(container.read(sharedStateProvider).setupParams?.selectedMap, {
        'My route': 'Safe',
        'GLOBAL': 'Safe',
        'Safe': '',
      });
    },
  );

  test('active pair clears manual pins only for its own group', () {
    final profile = Profile.normal().copyWith(
      selectedMap: const {
        'My route': 'Old node',
        'GLOBAL': 'Third node',
        'Other': 'Keep',
      },
      overrides: const ProfileOverrides(nodeFailover: pair),
    );
    final container = ProviderContainer(
      overrides: [
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        profilesProvider.overrideWith(() => TestProfiles([profile])),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(selectedMapProvider), {
      'My route': 'Safe',
      'GLOBAL': 'Safe',
      'Safe': '',
      'Other': 'Keep',
    });
    expect(
      container.read(profilesProvider).single.selectedMap,
      profile.selectedMap,
    );
    container
        .read(profilesProvider.notifier)
        .put(
          profile.copyWith(
            overrides: ProfileOverrides(
              nodeFailover: pair.copyWith(enabled: false),
            ),
          ),
        );
    expect(container.read(selectedMapProvider), profile.selectedMap);
  });

  test('node pair survives real SQLite profile persistence', () async {
    final database = db.Database(NativeDatabase.memory());
    addTearDown(database.close);
    final profile = Profile.normal(
      url: 'https://example.com/sub',
    ).copyWith(order: 0, overrides: const ProfileOverrides(nodeFailover: pair));
    await database.profilesDao.setAll([profile]);
    expect(await database.profilesDao.get(profile.id), profile);
  });
  test(
    'a stale leave-Safe rebuild cannot write into another profile',
    () async {
      final first = Profile.normal().copyWith(
        overrides: const ProfileOverrides(nodeFailover: pair),
      );
      final second = Profile.normal().copyWith(
        id: first.id + 1,
        selectedMap: const {'My route': 'Keep B'},
      );
      final setup = WaitingSetup();
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => first.id),
          profilesProvider.overrideWith(() => TestProfiles([first, second])),
          setupActionProvider.overrideWith(() => setup),
        ],
      );
      addTearDown(container.dispose);
      final action = container.read(proxiesActionProvider.notifier);
      action.changeProxyDebounce('My route', 'new A');
      debouncer.cancel((FunctionTag.changeProxy, 'My route'));
      final pending = action.changeProxy(
        groupName: 'My route',
        proxyName: 'new A',
      );
      expect(setup.entered, true);
      container.read(currentProfileIdProvider.notifier).value = second.id;
      setup.applied.complete(true);
      await pending;
      expect(
        container.read(currentProfileProvider)!.selectedMap,
        second.selectedMap,
      );
      expect(
        container.read(profilesProvider).first.overrides.nodeFailover!.enabled,
        false,
      );
      expect(
        container
            .read(profilesProvider)
            .first
            .overrides
            .nodeFailover!
            .backupKey,
        pair.backupKey,
      );
    },
  );
  test(
    'global to rule and global to direct to rule re-resolve the active Safe entry',
    () async {
      final profile = Profile.normal().copyWith(
        overrides: ProfileOverrides(
          nodeFailover: pair.copyWith(routeGroupName: 'GLOBAL'),
        ),
      );
      final setup = RecordingRebuildSetup();
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
          profilesProvider.overrideWith(() => TestProfiles([profile])),
          setupActionProvider.overrideWith(() => setup),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith(mode: Mode.global));
      container.read(setupActionProvider.notifier);
      setup.changeMode(Mode.rule);
      await container.pump();
      setup.changeMode(Mode.global);
      await container.pump();
      setup.changeMode(Mode.direct);
      await container.pump();
      setup.changeMode(Mode.rule);
      await container.pump();
      expect(setup.rebuilds, [
        (mode: Mode.rule, force: true),
        (mode: Mode.global, force: true),
        (mode: Mode.rule, force: true),
      ]);
    },
  );
}
