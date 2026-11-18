bool isSubscriptionUrl(String value) {
  final url = value.trim();
  if (RegExp(r'[\s\x00-\x1f\x7f]').hasMatch(url)) return false;
  final uri = Uri.tryParse(url);
  return uri != null &&
      uri.host.isNotEmpty &&
      const ['http', 'https'].contains(uri.scheme);
}

Future<void> runSubscriptionOnboarding({
  required Future<String?> Function(String value) requestUrl,
  required Future<bool> Function() hasProfiles,
  required Future<void> Function(String url) importSubscription,
  required Future<bool> Function() isPending,
  required Future<void> Function() complete,
}) async {
  var value = '';
  while (await isPending()) {
    if (await hasProfiles()) {
      await complete();
      return;
    }
    final input = await requestUrl(value);
    if (await hasProfiles()) {
      await complete();
      return;
    }
    if (input == null) return;
    value = input.trim();
    if (!isSubscriptionUrl(value)) continue;
    await importSubscription(value);
  }
}
