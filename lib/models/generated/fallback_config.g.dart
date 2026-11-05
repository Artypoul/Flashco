// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../fallback_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_FallbackConfig _$FallbackConfigFromJson(Map<String, dynamic> json) =>
    _FallbackConfig(
      selector: json['selector'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
      interval: (json['interval'] as num).toInt(),
      timeout: (json['timeout'] as num).toInt(),
      lazy: json['lazy'] as bool,
      expectedStatus: json['expected-status'] as String,
    );

Map<String, dynamic> _$FallbackConfigToJson(_FallbackConfig instance) =>
    <String, dynamic>{
      'selector': instance.selector,
      'name': instance.name,
      'url': instance.url,
      'interval': instance.interval,
      'timeout': instance.timeout,
      'lazy': instance.lazy,
      'expected-status': instance.expectedStatus,
    };
