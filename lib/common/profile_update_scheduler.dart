import 'dart:async';

import 'package:flashco/common/constant.dart';
import 'package:flashco/enum/enum.dart';
import 'package:flashco/models/profile.dart';

class ProfileUpdateScheduler {
  ProfileUpdateScheduler({
    required this.profiles,
    required this.update,
    required this.onError,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final List<Profile> Function() profiles;
  final Future<void> Function(Profile profile) update;
  final void Function(Object error, StackTrace stackTrace) onError;
  final DateTime Function() now;
  final _lastAttempt = <int, DateTime>{};
  Timer? _timer;
  bool _updating = false;
  bool _disposed = false;

  DateTime? _dueAt(Profile profile, DateTime currentTime) {
    if (!profile.autoUpdate || profile.type != ProfileType.url) return null;
    final interval = profile.autoUpdateDuration > Duration.zero
        ? profile.autoUpdateDuration
        : defaultUpdateDuration;
    var previous = profile.lastUpdateDate;
    final attempted = _lastAttempt[profile.id];
    if (attempted != null &&
        (previous == null || attempted.isAfter(previous))) {
      previous = attempted;
    }
    return previous?.add(interval) ?? currentTime;
  }

  void reschedule() {
    _timer?.cancel();
    if (_disposed || _updating) return;
    final currentTime = now();
    final currentProfiles = profiles();
    final ids = currentProfiles.map((profile) => profile.id).toSet();
    _lastAttempt.removeWhere((id, _) => !ids.contains(id));
    DateTime? next;
    for (final profile in currentProfiles) {
      final due = _dueAt(profile, currentTime);
      if (due != null && (next == null || due.isBefore(next))) next = due;
    }
    if (next == null) return;
    final delay = next.difference(currentTime);
    _timer = Timer(delay.isNegative ? Duration.zero : delay, _run);
  }

  Future<void> _run() async {
    if (_disposed || _updating) return;
    _updating = true;
    try {
      final ids = profiles().map((profile) => profile.id).toList();
      for (final id in ids) {
        if (_disposed) break;
        final profile = profiles()
            .where((profile) => profile.id == id)
            .firstOrNull;
        if (profile == null) continue;
        final due = _dueAt(profile, now());
        if (due == null || due.isAfter(now())) continue;
        try {
          await update(profile);
        } catch (error, stackTrace) {
          onError(error, stackTrace);
        } finally {
          _lastAttempt[id] = now();
        }
      }
    } finally {
      _updating = false;
      reschedule();
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
