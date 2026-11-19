import 'package:flashco/common/preferences.dart';
import 'package:flashco/flashco/subscription_onboarding.dart';

export 'package:flashco/flashco/subscription_onboarding.dart';

Future<void> requestFirstRunSubscription({
  required Future<String?> Function(String value) requestUrl,
  required Future<bool> Function() hasProfiles,
  required Future<void> Function(String url) importSubscription,
}) async {
  await runSubscriptionOnboarding(
    requestUrl: requestUrl,
    hasProfiles: hasProfiles,
    importSubscription: importSubscription,
    isPending: () => preferences.isSubscriptionOnboardingPending,
    complete: preferences.completeSubscriptionOnboarding,
  );
}
