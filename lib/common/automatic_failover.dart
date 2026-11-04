void applyAutomaticFailover(
  Map<dynamic, dynamic> config, {
  required bool enabled,
  required int interval,
  required String testUrl,
}) {
  if (!enabled) return;
  final rawGroups = config['proxy-groups'];
  if (rawGroups is! List) return;
  final nodes = {
    for (final proxy
        in (config['proxies'] as List? ?? const []).whereType<Map>())
      if (proxy['server'] is String && (proxy['server'] as String).isNotEmpty)
        proxy['name'],
  };
  final groups = {
    for (final group in rawGroups.whereType<Map>()) group['name']: group,
  };
  bool safe(dynamic name, Set<dynamic> visited) {
    if (nodes.contains(name)) return true;
    if (visited.contains(name)) return false;
    final group = groups[name];
    if (group == null) return false;
    final members = group['proxies'] as List? ?? const [];
    final providers = group['use'] as List? ?? const [];
    return (members.isNotEmpty || providers.isNotEmpty) &&
        members.every((member) => safe(member, {...visited, name}));
  }

  config['proxy-groups'] = [
    for (final group in rawGroups)
      if (group is Map && group['type'] == 'select' && safe(group['name'], {}))
        {
          ...group,
          'type': 'fallback',
          'fallback-mode': 'ordered',
          'url': testUrl,
          'interval': interval.clamp(1, 3600),
          'lazy': false,
          'empty-fallback': 'REJECT',
        }
      else
        group,
  ];
}
