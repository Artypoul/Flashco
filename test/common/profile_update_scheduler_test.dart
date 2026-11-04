import 'dart:async';

import 'package:flashco/common/profile_update_scheduler.dart';
import 'package:flashco/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new subscriptions use an editable ten-minute default', () {
    final profile = Profile.normal(url: 'https://example.com/sub');
    expect(profile.autoUpdate, isTrue);
    expect(profile.autoUpdateDuration, const Duration(minutes: 10));
    expect(
      profile
          .copyWith(autoUpdateDuration: const Duration(hours: 1))
          .autoUpdateDuration,
      const Duration(hours: 1),
    );
  });

  testWidgets('uses each saved interval and reschedules after edits', (
    tester,
  ) async {
    final now = tester.binding.clock.now;
    var profiles = [
      Profile.normal(url: 'https://example.com/one').copyWith(
        id: 1,
        lastUpdateDate: now(),
        autoUpdateDuration: const Duration(minutes: 10),
      ),
      Profile.normal(url: 'https://example.com/two').copyWith(
        id: 2,
        lastUpdateDate: now(),
        autoUpdateDuration: const Duration(minutes: 30),
      ),
      Profile.normal(
        url: 'https://example.com/disabled',
      ).copyWith(autoUpdate: false),
      Profile.normal(),
      Profile.custom(),
    ];
    final updated = <int>[];
    late final ProfileUpdateScheduler scheduler;
    scheduler = ProfileUpdateScheduler(
      profiles: () => profiles,
      now: now,
      update: (profile) async {
        updated.add(profile.id);
        profiles = [
          for (final p in profiles)
            p.id == profile.id ? p.copyWith(lastUpdateDate: now()) : p,
        ];
        scheduler.reschedule();
      },
      onError: (error, stack) => fail('$error'),
    );
    addTearDown(scheduler.dispose);
    scheduler.reschedule();
    await tester.pump(const Duration(minutes: 9));
    expect(updated, isEmpty);
    await tester.pump(const Duration(minutes: 1));
    expect(updated, [1]);
    profiles = [
      for (final p in profiles)
        p.id == 2
            ? p.copyWith(autoUpdateDuration: const Duration(minutes: 12))
            : p,
    ];
    scheduler.reschedule();
    await tester.pump(const Duration(minutes: 2));
    expect(updated, [1, 2]);
    profiles = [for (final p in profiles) p.copyWith(autoUpdate: false)];
    scheduler.reschedule();
    await tester.pump(const Duration(hours: 1));
    expect(updated, [1, 2]);
  });

  testWidgets('failed downloads retry at the saved interval without overlap', (
    tester,
  ) async {
    final now = tester.binding.clock.now;
    var profiles = [Profile.normal(url: 'https://example.com/sub')];
    final pending = Completer<void>();
    var attempts = 0;
    var errors = 0;
    final scheduler = ProfileUpdateScheduler(
      profiles: () => profiles,
      now: now,
      update: (_) async {
        attempts++;
        await pending.future;
        throw StateError('offline');
      },
      onError: (_, _) => errors++,
    );
    addTearDown(scheduler.dispose);
    scheduler.reschedule();
    await tester.pump(const Duration(milliseconds: 1));
    expect(attempts, 1);
    scheduler.reschedule();
    await tester.pump(const Duration(hours: 1));
    expect(attempts, 1);
    pending.complete();
    await tester.pump(const Duration(milliseconds: 1));
    expect(errors, 1);
    await tester.pump(const Duration(minutes: 9));
    expect(attempts, 1);
    await tester.pump(const Duration(minutes: 1));
    expect(attempts, 2);
    profiles = [];
    scheduler.reschedule();
    await tester.pump(const Duration(days: 1));
    expect(attempts, 2);
  });

  testWidgets('resume catches up and disposal cancels future updates', (
    tester,
  ) async {
    final now = tester.binding.clock.now;
    var profiles = <Profile>[];
    var updates = 0;
    final scheduler = ProfileUpdateScheduler(
      profiles: () => profiles,
      now: now,
      update: (_) async => updates++,
      onError: (_, _) {},
    );
    scheduler.reschedule();
    profiles = [
      Profile.normal(
        url: 'https://example.com/sub',
      ).copyWith(lastUpdateDate: now().subtract(const Duration(hours: 1))),
    ];
    scheduler.reschedule();
    await tester.pump(const Duration(milliseconds: 1));
    expect(updates, 1);
    scheduler.dispose();
    await tester.pump(const Duration(hours: 1));
    scheduler.reschedule();
    expect(updates, 1);
  });

  testWidgets('invalid legacy intervals fall back without a busy loop', (
    tester,
  ) async {
    var updates = 0;
    final profile = Profile.normal(
      url: 'https://example.com/sub',
    ).copyWith(autoUpdateDuration: Duration.zero);
    final scheduler = ProfileUpdateScheduler(
      profiles: () => [profile],
      now: tester.binding.clock.now,
      update: (_) async => updates++,
      onError: (_, _) {},
    );
    addTearDown(scheduler.dispose);
    scheduler.reschedule();
    await tester.pump(const Duration(milliseconds: 1));
    expect(updates, 1);
    await tester.pump(const Duration(minutes: 9));
    expect(updates, 1);
    await tester.pump(const Duration(minutes: 1));
    expect(updates, 2);
    scheduler.dispose();
  });
}
