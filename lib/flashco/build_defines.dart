const bundledSubscriptionUrl = String.fromEnvironment(
  'BOOTSTRAP_SUBSCRIPTION_URL',
);
const subscriptionOnFirstRun = bool.fromEnvironment(
  'BOOTSTRAP_SUBSCRIPTION_ON_FIRST_RUN',
);
const realitySupportX25519Mlkem768 = bool.fromEnvironment(
  'REALITY_SUPPORT_X25519MLKEM768',
);
const bundledFallbackConfig = String.fromEnvironment(
  'BOOTSTRAP_FALLBACK_CONFIG',
);
