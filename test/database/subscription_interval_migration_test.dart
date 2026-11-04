import 'package:drift/native.dart';
import 'package:flashco/database/database.dart';
import 'package:flashco/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test(
    'daily legacy defaults migrate once and preserve profile settings',
    () async {
      final raw = sqlite.sqlite3.openInMemory();
      var db = Database(
        NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
      );
      addTearDown(() async {
        await db.close();
        raw.close();
      });
      final daily = Profile.normal(url: 'https://example.com/daily').copyWith(
        id: 1,
        order: 0,
        autoUpdateDuration: const Duration(days: 1),
        selectedMap: const {'PROXY': 'Chosen node'},
        overrides: const ProfileOverrides(realityMlkemEnabled: false),
      );
      final custom = daily.copyWith(
        id: 2,
        order: 1,
        autoUpdateDuration: const Duration(hours: 2),
      );
      final disabled = daily.copyWith(id: 3, order: 2, autoUpdate: false);
      final local = Profile.normal().copyWith(
        id: 4,
        order: 3,
        autoUpdateDuration: const Duration(days: 1),
      );
      await db.profilesDao.setAll([daily, custom, disabled, local]);
      await db.close();
      raw.execute('PRAGMA user_version = 21');
      db = Database(NativeDatabase.opened(raw, closeUnderlyingOnClose: false));
      final migrated = await db.profilesDao.get(1);
      expect(
        migrated,
        daily.copyWith(autoUpdateDuration: const Duration(minutes: 10)),
      );
      expect(await db.profilesDao.get(2), custom);
      expect(
        await db.profilesDao.get(3),
        disabled.copyWith(autoUpdateDuration: const Duration(minutes: 10)),
      );
      expect(await db.profilesDao.get(4), local);
      await db.profilesDao.putAll([daily.toCompanion()]);
      await db.close();
      db = Database(NativeDatabase.opened(raw, closeUnderlyingOnClose: false));
      expect(await db.profilesDao.get(1), daily);
    },
  );
}
