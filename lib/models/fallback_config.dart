import 'package:freezed_annotation/freezed_annotation.dart';

part 'generated/fallback_config.freezed.dart';
part 'generated/fallback_config.g.dart';

@freezed
abstract class FallbackConfig with _$FallbackConfig {
  const FallbackConfig._();

  const factory FallbackConfig({
    required String selector,
    required String name,
    required String url,
    required int interval,
    required int timeout,
    required bool lazy,
    @JsonKey(name: 'expected-status') required String expectedStatus,
  }) = _FallbackConfig;

  factory FallbackConfig.fromJson(Map<String, dynamic> json) =>
      _$FallbackConfigFromJson(json);

  FallbackConfig validated() {
    final uri = Uri.tryParse(url);
    if (selector.trim().isEmpty ||
        name.trim().isEmpty ||
        selector == name ||
        uri == null ||
        uri.host.isEmpty ||
        !const ['http', 'https'].contains(uri.scheme) ||
        interval <= 0 ||
        timeout <= 0 ||
        timeout >= 65535) {
      throw const FormatException('Invalid fallback configuration');
    }
    return this;
  }
}
