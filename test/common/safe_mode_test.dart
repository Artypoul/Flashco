import 'package:flashco/common/common.dart';
import 'package:flashco/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> fixture() => {
  'proxies': [
    for (final network in ['xhttp', 'grpc', 'tcp'])
      {
        'name': network,
        'type': 'vless',
        'network': network,
        'server': 'example.test',
        'port': 443,
      },
  ],
  'proxy-groups': [
    {
      'name': 'PROXY',
      'type': 'select',
      'proxies': ['Fastest', 'xhttp', 'grpc', 'tcp'],
    },
    {
      'name': 'Fastest',
      'type': 'url-test',
      'proxies': ['xhttp', 'grpc', 'tcp'],
    },
  ],
  'rules': ['GEOIP,private,DIRECT', 'MATCH,PROXY'],
};

void main() {
  test(
    'Safe is available without configuration and preserves existing groups',
    () {
      final config = fixture();
      final original = Map.from((config['proxy-groups'] as List)[0]);
      applySafeNodeFailover(
        config,
        choice: null,
        interval: 27,
        testUrl: 'probe',
      );
      final groups = (config['proxy-groups'] as List).cast<Map>();
      final safe = groups.singleWhere((group) => group['name'] == 'Safe');
      expect(safe['type'], 'fallback');
      expect(safe['proxies'], ['xhttp', 'grpc', 'tcp']);
      expect(safe['interval'], 27);
      expect(safe['lazy'], false);
      expect(groups[0]['type'], original['type']);
      expect(groups[0], original);
      expect(groups[1]['type'], 'url-test');
      expect(config['rules'], ['GEOIP,private,DIRECT', 'MATCH,PROXY']);
    },
  );
  test(
    'explicit Safe pair follows endpoint identity and never adds a third node',
    () {
      final config = fixture();
      final nodes = profileFailoverNodes(config);
      final choice = ProfileNodeFailover(
        groupName: 'Safe',
        routeGroupName: 'PROXY',
        primaryKey: nodes[0].key,
        backupKey: nodes[1].key,
        primaryName: nodes[0].name,
        backupName: nodes[1].name,
      );
      (config['proxies'] as List)[0]['name'] = 'renamed';
      applySafeNodeFailover(
        config,
        choice: choice,
        interval: 15,
        testUrl: 'probe',
      );
      final safe = (config['proxy-groups'] as List).cast<Map>().singleWhere(
        (g) => g['name'] == 'Safe',
      );
      expect(safe['proxies'], ['renamed', 'grpc']);
      expect(safe['fallback-mode'], 'ordered');
      expect(safe['empty-fallback'], 'REJECT');
    },
  );
  test(
    'active parents are selectors so a failed pair cannot escape to siblings',
    () {
      final config = fixture();
      final nodes = safeProfileNodes(config);
      final choice = safeNodeChoice(
        config,
        null,
        nodeKey: nodes[0].key,
        backup: false,
      ).copyWith(backupKey: nodes[1].key);
      (config['proxy-groups'] as List)[0]['type'] = 'fallback';
      (config['proxy-groups'] as List)[0]['exclude-type'] = 'fallback';
      (config['proxy-groups'] as List)[0]['exclude-filter'] = 'Safe';
      (config['proxy-groups'] as List).add({
        'name': 'GLOBAL',
        'type': 'load-balance',
        'proxies': ['tcp'],
      });
      applySafeNodeFailover(
        config,
        choice: choice,
        interval: 15,
        testUrl: 'probe',
      );
      final groups = (config['proxy-groups'] as List).cast<Map>();
      expect(groups.first['type'], 'select');
      expect(groups.first['exclude-type'], isNull);
      expect(groups.first['exclude-filter'], isNull);
      expect(
        groups.singleWhere((g) => g['name'] == 'GLOBAL')['type'],
        'select',
      );
      expect(safeSelectedMap({'PROXY': 'tcp', 'GLOBAL': 'tcp'}, choice), {
        'PROXY': 'Safe',
        'GLOBAL': 'Safe',
        'Safe': '',
      });
      expect(groups.singleWhere((g) => g['name'] == 'Safe')['proxies'], [
        'xhttp',
        'grpc',
      ]);
    },
  );
  test(
    'legacy settings and renamed routes keep keys and resolve actual routing',
    () {
      final config = fixture();
      final nodes = safeProfileNodes(config);
      final old = ProfileNodeFailover(
        groupName: 'Old route',
        primaryKey: nodes[0].key,
        backupKey: nodes[1].key,
        primaryName: 'old label',
        backupName: 'old backup',
      );
      final migrated = resolvedSafeChoice(config, old)!;
      expect(migrated.groupName, 'Safe');
      expect(migrated.routeGroupName, 'PROXY');
      expect(migrated.primaryKey, old.primaryKey);
      expect(migrated.backupKey, old.backupKey);
    },
  );
  test('duplicate inline names retain distinct endpoint aliases and keys', () {
    final config = fixture();
    final proxies = config.remove('proxies') as List;
    proxies[0]['name'] = 'same';
    proxies[1]['name'] = 'same';
    config['proxy-providers'] = {
      'inline': {'type': 'inline', 'payload': proxies},
    };
    final nodes = safeProfileNodes(config);
    expect(nodes.map((n) => n.name).toSet(), hasLength(3));
    final selected = safeNodeChoice(
      config,
      null,
      nodeKey: nodes[1].key,
      backup: false,
    );
    applySafeNodeFailover(
      config,
      choice: selected,
      interval: 15,
      testUrl: 'probe',
    );
    final safe = (config['proxy-groups'] as List).cast<Map>().singleWhere(
      (g) => g['name'] == 'Safe',
    );
    expect((safe['proxies'] as List).first, nodes[1].name);
    expect(
      (config['proxies'] as List).cast<Map>().singleWhere(
        (p) => p['name'] == nodes[1].name,
      )['network'],
      'grpc',
    );
  });
  test(
    'MATCH resolves a load balancing route instead of an unrelated Fastest group',
    () {
      final config = fixture();
      (config['proxy-groups'] as List)[0]['type'] = 'load-balance';
      expect(safeRouteGroup(config), 'PROXY');
      final choice = safeNodeChoice(config, null, backup: false);
      expect(choice.routeGroupName, 'PROXY');
      applySafeNodeFailover(
        config,
        choice: choice,
        interval: 15,
        testUrl: 'probe',
      );
      expect((config['proxy-groups'] as List)[0]['type'], 'select');
    },
  );
  test('global Safe works without a subscription-defined GLOBAL group', () {
    final config = fixture();
    config['rules'] = [];
    final choice = safeNodeChoice(config, null, backup: false, global: true);
    expect(choice.routeGroupName, 'GLOBAL');
    applySafeNodeFailover(
      config,
      choice: choice,
      interval: 15,
      testUrl: 'probe',
    );
    expect(safeSelectedMap({}, choice)['GLOBAL'], 'Safe');
  });
  test('route choice uses effective added rules in native matching order', () {
    final config = fixture();
    (config['proxy-groups'] as List).add({
      'name': 'Other',
      'type': 'select',
      'proxies': ['tcp'],
    });
    config['rules'] = composeProfileRules(
      config,
      addedRules: [Rule.parse('MATCH,Other')],
    );
    expect(safeRouteGroup(config), 'Other');
    expect(safeNodeChoice(config, null, backup: false).routeGroupName, 'Other');
  });
  test('Safe does not overwrite subscription names', () {
    final config = fixture();
    (config['proxy-groups'] as List).add({
      'name': 'Safe',
      'type': 'select',
      'proxies': ['tcp'],
    });
    expect(safeGroupName(config), 'Safe (2)');
    applySafeNodeFailover(config, choice: null, interval: 15, testUrl: 'probe');
    expect(
      (config['proxy-groups'] as List).where((g) => g['name'] == 'Safe (2)'),
      hasLength(1),
    );
  });
}
