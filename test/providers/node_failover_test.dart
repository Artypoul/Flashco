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
  groupName: 'My route',
  primaryKey: 'a',
  backupKey: 'b',
  primaryName: 'Primary',
  backupName: 'Backup',
);

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
        'My route': '',
        'GLOBAL': 'My route',
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
      'My route': '',
      'GLOBAL': 'My route',
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
}
