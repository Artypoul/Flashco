import 'dart:convert';

typedef RealityMlkemNode = ({String key, String name});

String? realityMlkemKey(Map<dynamic, dynamic> proxy) {
  final reality = proxy['reality-opts'];
  final server = proxy['server'];
  final port = int.tryParse('${proxy['port']}');
  if (reality is! Map ||
      reality['public-key'] is! String ||
      (reality['public-key'] as String).isEmpty ||
      server is! String ||
      server.isEmpty ||
      port == null ||
      port < 1 ||
      port > 65535) {
    return null;
  }
  return jsonEncode([
    server.toLowerCase(),
    port,
    proxy['network'] ?? 'tcp',
    proxy['servername'] ?? proxy['sni'] ?? '',
  ]);
}

Iterable<Map<dynamic, dynamic>> _proxyDefinitions(
  Map<dynamic, dynamic> config,
) sync* {
  final proxies = config['proxies'];
  if (proxies is List) yield* proxies.whereType<Map>();
  final providers = config['proxy-providers'];
  if (providers is Map) {
    for (final provider in providers.values.whereType<Map>()) {
      if (provider['type'] == 'inline' && provider['payload'] is List) {
        yield* (provider['payload'] as List).whereType<Map>();
      }
    }
  }
}

List<RealityMlkemNode> realityMlkemNodes(Map<dynamic, dynamic> config) {
  final nodes = <String, RealityMlkemNode>{};
  for (final proxy in _proxyDefinitions(config)) {
    final key = realityMlkemKey(proxy);
    if (key != null) {
      nodes.putIfAbsent(
        key,
        () => (key: key, name: '${proxy['name'] ?? proxy['server']}'),
      );
    }
  }
  return nodes.values.toList();
}

void applyRealityMlkemOverrides(
  Map<dynamic, dynamic> config,
  Map<String, bool> overrides, {
  required bool enabledByDefault,
}) {
  List<dynamic> apply(List<dynamic> proxies) => [
    for (final proxy in proxies)
      if (proxy is Map && realityMlkemKey(proxy) != null)
        {
          ...proxy,
          'reality-opts': {
            ...proxy['reality-opts'] as Map,
            'support-x25519mlkem768':
                overrides[realityMlkemKey(proxy)] ?? enabledByDefault,
          },
        }
      else
        proxy,
  ];
  if (config['proxies'] case final List proxies) {
    config['proxies'] = apply(proxies);
  }
  if (config['proxy-providers'] case final Map providers) {
    config['proxy-providers'] = {
      for (final entry in providers.entries)
        entry.key: switch (entry.value) {
          {'type': 'inline', 'payload': final List payload} => {
            ...entry.value as Map,
            'payload': apply(payload),
          },
          _ => entry.value,
        },
    };
  }
}
