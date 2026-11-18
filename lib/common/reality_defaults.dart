import 'package:flashco/common/constant.dart';

const _realityCondition =
    '(.reality-opts | type) == "!!map" and '
    '(.reality-opts.public-key | type) == "!!str" and '
    '.reality-opts.public-key != ""';
const _providerDefaults = [
  '(select($_realityCondition and '
      '(.reality-opts | has("support-x25519mlkem768") | not)) | '
      '.reality-opts.support-x25519mlkem768) = true',
  '(select($_realityCondition and (has("client-fingerprint") | not)) | '
      '.client-fingerprint) = "chrome"',
];

Map<String, dynamic> applyRealityDefaults(
  Map<String, dynamic> config, {
  bool enabled = realitySupportX25519Mlkem768,
}) {
  if (!enabled) return config;
  final proxies = config['proxies'];
  final providers = config['proxy-providers'];
  return {
    ...config,
    if (proxies is List)
      'proxies': [for (final proxy in proxies) _proxyDefaults(proxy)],
    if (providers is Map)
      'proxy-providers': {
        for (final entry in providers.entries)
          entry.key: _providerOverride(entry.value),
      },
  };
}

dynamic _proxyDefaults(dynamic proxy) {
  if (proxy is! Map) return proxy;
  final reality = proxy['reality-opts'];
  if (reality is! Map) return proxy;
  final publicKey = reality['public-key'];
  if (publicKey is! String || publicKey.isEmpty) return proxy;
  return {
    ...proxy,
    if (!proxy.containsKey('client-fingerprint'))
      'client-fingerprint': 'chrome',
    'reality-opts': {'support-x25519mlkem768': true, ...reality},
  };
}

dynamic _providerOverride(dynamic provider) {
  if (provider is! Map) return provider;
  final override = provider['override'];
  if (override != null && override is! Map) return provider;
  final expressions = override?['override-expr'];
  if (expressions != null && expressions is! List) return provider;
  if (expressions is List &&
      expressions.length >= _providerDefaults.length &&
      _providerDefaults.indexed.every(
        (entry) =>
            expressions[expressions.length -
                _providerDefaults.length +
                entry.$1] ==
            entry.$2,
      )) {
    return provider;
  }
  return {
    ...provider,
    'override': {
      if (override is Map) ...override,
      'override-expr': [
        if (expressions is List) ...expressions,
        ..._providerDefaults,
      ],
    },
  };
}
