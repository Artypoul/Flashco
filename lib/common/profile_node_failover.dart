import 'dart:convert';

import 'package:flashco/enum/enum.dart';
import 'package:flashco/models/clash_config.dart';

typedef ProfileFailoverNode = ({String key, String name, Map definition});

String? profileFailoverNodeKey(Map proxy) {
  final server = proxy['server'];
  final port = int.tryParse('${proxy['port']}');
  final type = proxy['type'];
  if (server is! String ||
      server.isEmpty ||
      type is! String ||
      port == null ||
      port < 1 ||
      port > 65535) {
    return null;
  }
  Object? ordered(Object? value) => switch (value) {
    final Map map => {
      for (final key in map.keys.map((key) => '$key').toList()..sort())
        key: ordered(map[key]),
    },
    final List list => list.map(ordered).toList(),
    _ => value,
  };
  Object? normalizedHost(Object? value) => switch (value) {
    final String host => host.toLowerCase(),
    final List hosts => hosts.map(normalizedHost).toList(),
    _ => value,
  };
  Object? transportIdentity(Object? value) {
    if (value is! Map) return null;
    final headers = value['headers'];
    final identity = {
      for (final field in ['path', 'host', 'grpc-service-name', 'service-name'])
        if (value.containsKey(field))
          field: field == 'host' ? normalizedHost(value[field]) : value[field],
      if (headers is Map)
        for (final entry in headers.entries)
          if ('${entry.key}'.toLowerCase() == 'host')
            'host-header': normalizedHost(entry.value),
    };
    return identity.isEmpty ? null : ordered(identity);
  }

  return jsonEncode([
    type.toLowerCase(),
    server.toLowerCase(),
    port,
    proxy['network'] ?? 'tcp',
    proxy['servername'] ?? proxy['sni'] ?? '',
    for (final option in [
      'ws-opts',
      'grpc-opts',
      'xhttp-opts',
      'http-opts',
      'h2-opts',
    ])
      transportIdentity(proxy[option]),
  ]);
}

List<ProfileFailoverNode> profileFailoverNodes(Map config) {
  final proxies = <Map>[
    ...((config['proxies'] as List?) ?? const []).whereType<Map>(),
    if (config['proxy-providers'] case final Map providers)
      for (final provider in providers.values.whereType<Map>())
        if (provider['type'] == 'inline' && _canMaterializeProvider(provider))
          ...((provider['payload'] as List?) ?? const []).whereType<Map>(),
  ];
  final nodes = <String, ProfileFailoverNode>{};
  for (final proxy in proxies) {
    final key = profileFailoverNodeKey(proxy);
    final name = proxy['name'];
    if (key != null && name is String && name.isNotEmpty) {
      nodes.putIfAbsent(key, () => (key: key, name: name, definition: proxy));
    }
  }
  return nodes.values.toList();
}

bool _canMaterializeProvider(Map provider) {
  final overrides = provider['override'];
  return (overrides == null || overrides is Map && overrides.isEmpty) &&
      [
        'dialer-proxy',
        'filter',
        'exclude-filter',
        'exclude-type',
      ].every((key) => provider[key] == null || provider[key] == '');
}

List<String> profileFailoverGroups(Map config) => [
  for (final group
      in ((config['proxy-groups'] as List?) ?? const []).whereType<Map>())
    if (group['name'] is String &&
        const ['select', 'fallback', 'url-test'].contains(group['type']))
      group['name'] as String,
];

void applyProfileNodeFailover(
  Map config, {
  required ProfileNodeFailover? choice,
  required int interval,
  required String testUrl,
}) {
  if (choice == null || !choice.enabled) return;
  final groups = config['proxy-groups'] as List? ?? const [];
  if (!profileFailoverGroups(config).contains(choice.groupName)) {
    throw const FormatException('The saved failover group is missing');
  }
  if (choice.primaryKey == choice.backupKey) {
    throw const FormatException('Primary and backup nodes must differ');
  }
  final nodes = {
    for (final node in profileFailoverNodes(config)) node.key: node,
  };
  final proxies = List<dynamic>.from(config['proxies'] as List? ?? const []);
  final members = <String>[];
  for (final key in [choice.primaryKey, choice.backupKey]) {
    final node = nodes[key];
    if (node == null) continue;
    final existing = proxies
        .whereType<Map>()
        .where((proxy) => profileFailoverNodeKey(proxy) == key)
        .firstOrNull;
    if (existing != null) {
      members.add(existing['name'] as String);
    } else {
      final names = proxies
          .whereType<Map>()
          .map((proxy) => proxy['name'])
          .toSet();
      names.addAll(groups.whereType<Map>().map((group) => group['name']));
      names.addAll(const {
        'GLOBAL',
        'DIRECT',
        'REJECT',
        'REJECT-DROP',
        'COMPATIBLE',
        'PASS',
        'PASS-RULE',
      });
      var name = node.name;
      for (var suffix = 2; names.contains(name); suffix++) {
        name = '${node.name} ($suffix)';
      }
      proxies.add({...node.definition, 'name': name});
      members.add(name);
    }
  }
  config['proxies'] = proxies;
  config['proxy-groups'] = [
    for (final group in groups)
      if (group is Map && group['name'] == choice.groupName)
        {
          'name': choice.groupName,
          'type': 'fallback',
          'proxies': members.isEmpty ? ['REJECT'] : members,
          'fallback-mode': 'ordered',
          'empty-fallback': 'REJECT',
          'url': testUrl,
          'interval': interval.clamp(1, 3600),
          'lazy': false,
          if (group.containsKey('icon')) 'icon': group['icon'],
          if (group.containsKey('hidden')) 'hidden': group['hidden'],
          if (group.containsKey('disable-udp'))
            'disable-udp': group['disable-udp'],
        }
      else
        group,
  ];
  final globalName = GroupName.GLOBAL.name;
  if (choice.groupName != globalName) {
    final pairedGroups = config['proxy-groups'] as List;
    final previous = pairedGroups
        .whereType<Map>()
        .where((group) => group['name'] == globalName)
        .firstOrNull;
    config['proxy-groups'] = [
      for (final group in pairedGroups)
        if (group is! Map || group['name'] != globalName) group,
      {
        'name': globalName,
        'type': 'select',
        'proxies': [choice.groupName],
        if (previous?.containsKey('icon') == true) 'icon': previous!['icon'],
      },
    ];
  }
}
