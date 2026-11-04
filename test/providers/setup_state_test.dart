import 'package:drift/native.dart';
import 'package:flashco/database/database.dart' as db;
import 'package:flashco/enum/enum.dart';
import 'package:flashco/models/models.dart';
import 'package:flashco/providers/database.dart';
import 'package:flashco/providers/state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_profiles.dart';

void main() {
  late db.Database testDatabase;

  setUp(() {
    testDatabase = db.Database(NativeDatabase.memory());
    db.database = testDatabase;
  });

  tearDown(() async {
    await testDatabase.close();
  });

  test('all profile types carry saved ML-KEM settings into setup', () async {
    for (final type in [
      ProfileType.url,
      ProfileType.file,
      ProfileType.custom,
    ]) {
      final profile = Profile(
        id: 1,
        type: type,
        autoUpdateDuration: Duration.zero,
        overrides: const ProfileOverrides(
          autoReconnect: false,
          autoFailover: false,
          reconnectInterval: 23,
          nodeFailover: ProfileNodeFailover(
            groupName: 'Route',
            primaryKey: 'a',
            backupKey: 'b',
            primaryName: 'A',
            backupName: 'B',
          ),
          realityMlkemEnabled: false,
          realityMlkem: {'node': true},
        ),
      );
      final container = ProviderContainer(
        overrides: [
          profilesProvider.overrideWith(() => TestProfiles([profile])),
        ],
      );
      addTearDown(container.dispose);
      final hold = container.listen(setupStateProvider(profile.id), (_, _) {});
      addTearDown(hold.close);
      final state = await container.read(setupStateProvider(profile.id).future);
      expect(state.overrides.autoReconnect, false);
      expect(state.overrides.autoFailover, false);
      expect(state.overrides.reconnectInterval, 23);
      expect(state.overrides.nodeFailover, profile.overrides.nodeFailover);
      expect(state.overrides.realityMlkemEnabled, false);
      expect(state.overrides.realityMlkem, {'node': true});
    }
  });

  testWidgets('a custom setup disposed before its queries return resolves', (
    tester,
  ) async {
    const profile = Profile(
      id: 1,
      label: 'Home',
      type: ProfileType.custom,
      autoUpdateDuration: Duration.zero,
    );
    const subscription = Profile(
      id: 2,
      label: 'Sub',
      type: ProfileType.url,
      url: 'https://example.com/sub',
      autoUpdateDuration: Duration.zero,
    );
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(
          () => TestProfiles([profile, subscription]),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const SizedBox.shrink(),
      ),
    );

    final state = await container.read(setupStateProvider(profile.id).future);

    expect(state.profileType, ProfileType.custom);
    expect(state.profileProviders, {'Sub': subscription.id});
  });

  testWidgets('a custom setup leaves the extension of its profile out', (
    tester,
  ) async {
    const profile = Profile(
      id: 1,
      type: ProfileType.custom,
      autoUpdateDuration: Duration.zero,
      extendType: ExtendType.script,
      scriptId: 5,
      matchTarget: 'Proxy',
    );
    await testDatabase.profilesDao.putAll([profile.toCompanion()]);
    await testDatabase.scripts.put(
      Script(
        id: 5,
        label: 'Script',
        lastUpdateTime: DateTime(2026),
      ).toCompanion(),
    );
    await testDatabase.rulesDao.putRule(
      Rule.parse('DOMAIN,global.com,DIRECT', id: 10),
    );
    await testDatabase.rulesDao.putRule(
      Rule.parse('DOMAIN,own.com,DIRECT', id: 11),
      profileId: profile.id,
    );
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles([profile])),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const SizedBox.shrink(),
      ),
    );

    final state = await container.read(setupStateProvider(profile.id).future);

    expect(state.script, isNull);
    expect(state.matchTarget, isNull);
    expect(state.addedRules, isEmpty);
    expect(state.rules.map((rule) => rule.id), [11]);
  });

  testWidgets('a custom setup carries the dialers of its own profile', (
    tester,
  ) async {
    const profile = Profile(
      id: 1,
      label: 'Home',
      type: ProfileType.custom,
      autoUpdateDuration: Duration.zero,
    );
    const other = Profile(
      id: 2,
      type: ProfileType.custom,
      autoUpdateDuration: Duration.zero,
    );
    await testDatabase.profilesDao.putAll([
      profile.toCompanion(),
      other.toCompanion(),
    ]);
    await testDatabase.customProxies.put(
      const CustomProxy(id: 30, definition: {'name': 'Home'}).toCompanion(),
    );
    await testDatabase.proxyDialersDao.set(profile.id, 30, 'Relay');
    await testDatabase.proxyDialersDao.set(other.id, 30, 'Other');
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles([profile, other])),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const SizedBox.shrink(),
      ),
    );

    final state = await container.read(setupStateProvider(profile.id).future);

    expect(state.proxyDialers, {30: 'Relay'});
  });
}
