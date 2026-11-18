import 'package:collection/collection.dart';
import 'package:flashco/models/fallback_config.dart';

({Map<String, dynamic> config, String name}) applyProfileFallback(
  Map<String, dynamic> input,
  FallbackConfig settings,
) {
  settings.validated();
  final groups =
      (input['proxy-groups'] as List?)?.whereType<Map>().toList() ?? [];
  final target = groups.indexWhere(
    (group) => group['name'] == settings.selector,
  );
  if (target < 0 || groups[target]['type'] != 'select') {
    throw const FormatException('Fallback target must be an existing selector');
  }
  final proxies = (input['proxies'] as List?)?.whereType<Map>() ?? const [];
  final names = <String>{
    for (final proxy in proxies)
      if (proxy['name'] case final String name)
        if (!const {
          'direct',
          'reject',
          'reject-drop',
          'pass',
          'dns',
          'compatible',
        }.contains(proxy['type']?.toString().toLowerCase()))
          name,
  }.toList();
  final providers = Map<String, dynamic>.from(
    input['proxy-providers'] as Map? ?? const {},
  );
  if (names.isEmpty && providers.isEmpty) {
    throw const FormatException('Fallback needs at least one proxy server');
  }
  final checks = {
    'url': settings.url,
    'interval': settings.interval,
    'timeout': settings.timeout,
    'lazy': settings.lazy,
    'expected-status': settings.expectedStatus,
  };
  Map<String, dynamic> definition(String name) => {
    'name': name,
    'type': 'fallback',
    'empty-fallback': 'REJECT',
    if (names.isNotEmpty) 'proxies': names,
    if (providers.isNotEmpty) 'use': providers.keys.toList(),
    'exclude-type': 'Direct|Reject|RejectDrop|Pass|DNS|Compatible',
    ...checks,
  };
  final occupied = {
    'DIRECT',
    'REJECT',
    'GLOBAL',
    for (final proxy in proxies)
      if (proxy['name'] case final String proxyName) proxyName,
    ...providers.keys,
    for (final group in groups) group['name'],
  };
  var name = settings.name;
  var suffix = 0;
  var existing = -1;
  while (occupied.contains(name)) {
    existing = groups.indexWhere(
      (group) => const DeepCollectionEquality().equals(group, definition(name)),
    );
    if (existing >= 0) break;
    name = '${settings.name} (${++suffix})';
  }
  final selector = Map<String, dynamic>.from(groups[target])
    ..['proxies'] = [
      name,
      for (final member in groups[target]['proxies'] as List? ?? const [])
        if (member != name) member,
    ];
  return (
    name: name,
    config: {
      ...input,
      'proxy-groups': [
        for (final (index, group) in groups.indexed)
          if (index == target) selector else group,
        if (existing < 0) definition(name),
      ],
      if (providers.isNotEmpty)
        'proxy-providers': {
          for (final MapEntry(:key, :value) in providers.entries)
            key: {
              ...Map<String, dynamic>.from(value as Map),
              'health-check': {
                ...Map<String, dynamic>.from(
                  value['health-check'] as Map? ?? const {},
                ),
                'enable': true,
                ...checks,
              },
            },
        },
    },
  );
}
