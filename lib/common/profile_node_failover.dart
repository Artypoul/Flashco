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
        const [
          'select',
          'fallback',
          'url-test',
          'load-balance',
          'relay',
        ].contains(group['type']))
      group['name'] as String,
];

String safeGroupName(Map config) {
  final names = {
    for (final group
        in (config['proxy-groups'] as List? ?? const []).whereType<Map>())
      group['name'],
    for (final proxy
        in (config['proxies'] as List? ?? const []).whereType<Map>())
      proxy['name'],
    for (final node in profileFailoverNodes(config)) node.name,
  };
  var name = 'Safe';
  for (var suffix = 2; names.contains(name); suffix++) {
    name = 'Safe ($suffix)';
  }
  return name;
}

String safeRouteGroup(Map config) {
  final names = profileFailoverGroups(config);
  for (final rule
      in (config['rules'] as List? ?? const []).whereType<String>()) {
    final parts = rule.split(',').map((part) => part.trim()).toList();
    if (parts.length == 2 &&
        const ['MATCH', 'FINAL'].contains(parts.first.toUpperCase())) {
      return names.contains(parts[1]) ? parts[1] : '';
    }
  }
  return '';
}

ProfileNodeFailover? resolvedSafeChoice(
  Map config,
  ProfileNodeFailover? choice, {
  bool global = false,
}) {
  if (choice == null) return null;
  final route = global ? GroupName.GLOBAL.name : safeRouteGroup(config);
  return choice.copyWith(
    groupName: safeGroupName(config),
    routeGroupName: route,
  );
}

List<ProfileFailoverNode> safeProfileNodes(Map config) {
  final originals = (config['proxies'] as List? ?? const [])
      .whereType<Map>()
      .toList();
  final names = <Object?>{
    safeGroupName(config),
    for (final group
        in (config['proxy-groups'] as List? ?? const []).whereType<Map>())
      group['name'],
    for (final proxy in originals) proxy['name'],
    'GLOBAL',
    'DIRECT',
    'REJECT',
    'REJECT-DROP',
    'COMPATIBLE',
    'PASS',
    'PASS-RULE',
  };
  return [
    for (final node in profileFailoverNodes(config))
      () {
        final existing = originals
            .where((proxy) => profileFailoverNodeKey(proxy) == node.key)
            .firstOrNull;
        var alias = existing?['name'] as String? ?? node.name;
        if (existing == null) {
          for (var suffix = 2; names.contains(alias); suffix++) {
            alias = '${node.name} ($suffix)';
          }
        }
        names.add(alias);
        return (
          key: node.key,
          name: alias,
          definition: {...node.definition, 'name': alias},
        );
      }(),
  ];
}

Map<String, String> safeSelectedMap(
  Map<String, String> selected,
  ProfileNodeFailover? choice,
) => {
  ...selected,
  if (choice?.enabled == true) ...{
    choice!.groupName: '',
    if (choice.routeGroupName?.isNotEmpty == true)
      choice.routeGroupName!: choice.groupName,
    GroupName.GLOBAL.name: choice.groupName,
  },
};

void applySafeNodeFailover(
  Map config, {
  required ProfileNodeFailover? choice,
  required int interval,
  required String testUrl,
}) {
  final name = safeGroupName(config);
  final nodes = safeProfileNodes(config);
  final byKey = {for (final node in nodes) node.key: node};
  final selected = choice == null
      ? nodes
      : [
          ?byKey[choice.primaryKey],
          if (choice.backupKey.isEmpty)
            ...nodes.where((node) => node.key != choice.primaryKey)
          else if (choice.backupKey != choice.primaryKey &&
              byKey[choice.backupKey] != null)
            byKey[choice.backupKey]!,
        ];
  final groups = List<dynamic>.from(
    config['proxy-groups'] as List? ?? const [],
  );
  final proxies = List<dynamic>.from(config['proxies'] as List? ?? const []);
  for (final node in nodes) {
    if (!proxies.whereType<Map>().any(
      (p) => profileFailoverNodeKey(p) == node.key,
    )) {
      proxies.add(node.definition);
    }
  }
  final members = [for (final node in selected) node.name];
  config['proxies'] = proxies;
  final route = choice?.routeGroupName ?? safeRouteGroup(config);
  if (choice?.enabled == true && route.isEmpty) {
    throw const FormatException('No selectable Safe route group');
  }
  if (choice?.enabled == true &&
      route != GroupName.GLOBAL.name &&
      !groups.whereType<Map>().any((group) => group['name'] == route)) {
    throw const FormatException('The saved Safe route group is missing');
  }
  config['proxy-groups'] = [
    for (final group in groups)
      if (choice?.enabled == true &&
          group is Map &&
          (group['name'] == route || group['name'] == 'GLOBAL'))
        {
          for (final entry in group.entries)
            if (!const ['exclude-filter', 'exclude-type'].contains(entry.key))
              entry.key: entry.value,
          'type': 'select',
          'proxies': [name, ...?group['proxies'] as List?],
          if (group.containsKey('icon')) 'icon': group['icon'],
          if (group.containsKey('hidden')) 'hidden': group['hidden'],
        }
      else
        group,
    {
      'name': name,
      'type': 'fallback',
      'proxies': members.isEmpty ? ['REJECT'] : members,
      'fallback-mode': 'ordered',
      'empty-fallback': 'REJECT',
      'url': testUrl,
      'interval': interval.clamp(1, 3600),
      'lazy': false,
    },
  ];
}

ProfileNodeFailover safeNodeChoice(
  Map config,
  ProfileNodeFailover? previous, {
  String? nodeKey,
  required bool backup,
  bool global = false,
}) {
  final nodes = safeProfileNodes(config);
  final byKey = {for (final node in nodes) node.key: node};
  if (nodes.isEmpty || nodeKey != null && !byKey.containsKey(nodeKey)) {
    throw const FormatException('The selected Safe node is missing');
  }
  var primary = previous?.primaryKey ?? nodes.first.key;
  var reserve = previous?.backupKey ?? '';
  if (backup) {
    reserve = nodeKey ?? '';
    if (reserve == primary) {
      primary =
          byKey.keys.where((key) => key != reserve).firstOrNull ?? primary;
      if (reserve == primary) reserve = '';
    }
  } else if (nodeKey != null) {
    if (reserve == nodeKey) reserve = primary == nodeKey ? '' : primary;
    primary = nodeKey;
  }
  final route = global ? GroupName.GLOBAL.name : safeRouteGroup(config);
  return ProfileNodeFailover(
    groupName: safeGroupName(config),
    routeGroupName: route,
    primaryKey: primary,
    backupKey: reserve,
    primaryName: byKey[primary]?.name ?? previous?.primaryName ?? '',
    backupName:
        byKey[reserve]?.name ??
        (reserve.isEmpty ? '' : previous?.backupName ?? ''),
  );
}

List<String> composeProfileRules(
  Map config, {
  List<Rule> rules = const [],
  List<Rule> addedRules = const [],
  String? matchTarget,
}) {
  var result = <String>[];
  if (rules.isEmpty) {
    if (config['rules'] != null) {
      result = List<String>.from(config['rules']);
    }
    if (addedRules.isNotEmpty) {
      final hasMatchPlaceholder = addedRules.any(
        (item) => item.ruleTarget?.toUpperCase() == 'MATCH',
      );
      String? replacementTarget = matchTarget?.trim();
      if (replacementTarget?.isEmpty == true) {
        replacementTarget = null;
      }

      if (hasMatchPlaceholder && replacementTarget == null) {
        for (int i = result.length - 1; i >= 0; i--) {
          final parsed = Rule.parse(result[i]);
          if (parsed.ruleAction == RuleAction.MATCH) {
            final target = parsed.ruleTarget;
            if (target != null && target.isNotEmpty) {
              replacementTarget = target;
              break;
            }
          }
        }
      }
      final List<String> finalAddedRules;

      if (replacementTarget?.isNotEmpty == true) {
        finalAddedRules = [];
        for (int i = 0; i < addedRules.length; i++) {
          final parsed = addedRules[i];
          if (parsed.ruleTarget?.toUpperCase() == 'MATCH') {
            finalAddedRules.add(
              parsed.copyWith(ruleTarget: replacementTarget).rawValue,
            );
          } else {
            finalAddedRules.add(addedRules[i].rawValue);
          }
        }
      } else {
        finalAddedRules = addedRules.map((e) => e.rawValue).toList();
      }
      result = [...finalAddedRules, ...result];
    }
  } else {
    result = rules.map((item) => item.rawValue).toList();
  }
  return result;
}
