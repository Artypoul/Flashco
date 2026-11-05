// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of '../fallback_config.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$FallbackConfig {

 String get selector; String get name; String get url; int get interval; int get timeout; bool get lazy;@JsonKey(name: 'expected-status') String get expectedStatus;
/// Create a copy of FallbackConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FallbackConfigCopyWith<FallbackConfig> get copyWith => _$FallbackConfigCopyWithImpl<FallbackConfig>(this as FallbackConfig, _$identity);

  /// Serializes this FallbackConfig to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as FallbackConfig;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FallbackConfig&&(identical(other.selector, _this.selector) || other.selector == _this.selector)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.url, _this.url) || other.url == _this.url)&&(identical(other.interval, _this.interval) || other.interval == _this.interval)&&(identical(other.timeout, _this.timeout) || other.timeout == _this.timeout)&&(identical(other.lazy, _this.lazy) || other.lazy == _this.lazy)&&(identical(other.expectedStatus, _this.expectedStatus) || other.expectedStatus == _this.expectedStatus));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as FallbackConfig;
  return Object.hash(runtimeType,_this.selector,_this.name,_this.url,_this.interval,_this.timeout,_this.lazy,_this.expectedStatus);
}

@override
String toString() {
  final _this = this as FallbackConfig;
  return 'FallbackConfig(selector: ${_this.selector}, name: ${_this.name}, url: ${_this.url}, interval: ${_this.interval}, timeout: ${_this.timeout}, lazy: ${_this.lazy}, expectedStatus: ${_this.expectedStatus})';
}


}

/// @nodoc
abstract mixin class $FallbackConfigCopyWith<$Res>  {
  factory $FallbackConfigCopyWith(FallbackConfig value, $Res Function(FallbackConfig) _then) = _$FallbackConfigCopyWithImpl;
@useResult
$Res call({
 String selector, String name, String url, int interval, int timeout, bool lazy,@JsonKey(name: 'expected-status') String expectedStatus
});




}
/// @nodoc
class _$FallbackConfigCopyWithImpl<$Res>
    implements $FallbackConfigCopyWith<$Res> {
  _$FallbackConfigCopyWithImpl(this._self, this._then);

  final FallbackConfig _self;
  final $Res Function(FallbackConfig) _then;

/// Create a copy of FallbackConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? selector = null,Object? name = null,Object? url = null,Object? interval = null,Object? timeout = null,Object? lazy = null,Object? expectedStatus = null,}) {
  return _then(FallbackConfig(
selector: null == selector ? _self.selector : selector // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,interval: null == interval ? _self.interval : interval // ignore: cast_nullable_to_non_nullable
as int,timeout: null == timeout ? _self.timeout : timeout // ignore: cast_nullable_to_non_nullable
as int,lazy: null == lazy ? _self.lazy : lazy // ignore: cast_nullable_to_non_nullable
as bool,expectedStatus: null == expectedStatus ? _self.expectedStatus : expectedStatus // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [FallbackConfig].
extension FallbackConfigPatterns on FallbackConfig {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FallbackConfig value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FallbackConfig() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FallbackConfig value)  $default,){
final _that = this;
switch (_that) {
case _FallbackConfig():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FallbackConfig value)?  $default,){
final _that = this;
switch (_that) {
case _FallbackConfig() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String selector,  String name,  String url,  int interval,  int timeout,  bool lazy, @JsonKey(name: 'expected-status')  String expectedStatus)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FallbackConfig() when $default != null:
return $default(_that.selector,_that.name,_that.url,_that.interval,_that.timeout,_that.lazy,_that.expectedStatus);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String selector,  String name,  String url,  int interval,  int timeout,  bool lazy, @JsonKey(name: 'expected-status')  String expectedStatus)  $default,) {final _that = this;
switch (_that) {
case _FallbackConfig():
return $default(_that.selector,_that.name,_that.url,_that.interval,_that.timeout,_that.lazy,_that.expectedStatus);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String selector,  String name,  String url,  int interval,  int timeout,  bool lazy, @JsonKey(name: 'expected-status')  String expectedStatus)?  $default,) {final _that = this;
switch (_that) {
case _FallbackConfig() when $default != null:
return $default(_that.selector,_that.name,_that.url,_that.interval,_that.timeout,_that.lazy,_that.expectedStatus);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _FallbackConfig extends FallbackConfig {
  const _FallbackConfig({required this.selector, required this.name, required this.url, required this.interval, required this.timeout, required this.lazy, @JsonKey(name: 'expected-status') required this.expectedStatus}): super._();
  factory _FallbackConfig.fromJson(Map<String, dynamic> json) => _$FallbackConfigFromJson(json);

@override final  String selector;
@override final  String name;
@override final  String url;
@override final  int interval;
@override final  int timeout;
@override final  bool lazy;
@override@JsonKey(name: 'expected-status') final  String expectedStatus;

/// Create a copy of FallbackConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FallbackConfigCopyWith<_FallbackConfig> get copyWith => __$FallbackConfigCopyWithImpl<_FallbackConfig>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$FallbackConfigToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _FallbackConfig&&(identical(other.selector, selector) || other.selector == selector)&&(identical(other.name, name) || other.name == name)&&(identical(other.url, url) || other.url == url)&&(identical(other.interval, interval) || other.interval == interval)&&(identical(other.timeout, timeout) || other.timeout == timeout)&&(identical(other.lazy, lazy) || other.lazy == lazy)&&(identical(other.expectedStatus, expectedStatus) || other.expectedStatus == expectedStatus));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,selector,name,url,interval,timeout,lazy,expectedStatus);
}

@override
String toString() {
    return 'FallbackConfig(selector: $selector, name: $name, url: $url, interval: $interval, timeout: $timeout, lazy: $lazy, expectedStatus: $expectedStatus)';
}


}

/// @nodoc
abstract mixin class _$FallbackConfigCopyWith<$Res> implements $FallbackConfigCopyWith<$Res> {
  factory _$FallbackConfigCopyWith(_FallbackConfig value, $Res Function(_FallbackConfig) _then) = __$FallbackConfigCopyWithImpl;
@override @useResult
$Res call({
 String selector, String name, String url, int interval, int timeout, bool lazy,@JsonKey(name: 'expected-status') String expectedStatus
});




}
/// @nodoc
class __$FallbackConfigCopyWithImpl<$Res>
    implements _$FallbackConfigCopyWith<$Res> {
  __$FallbackConfigCopyWithImpl(this._self, this._then);

  final _FallbackConfig _self;
  final $Res Function(_FallbackConfig) _then;

/// Create a copy of FallbackConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? selector = null,Object? name = null,Object? url = null,Object? interval = null,Object? timeout = null,Object? lazy = null,Object? expectedStatus = null,}) {
  return _then(_FallbackConfig(
selector: null == selector ? _self.selector : selector // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,interval: null == interval ? _self.interval : interval // ignore: cast_nullable_to_non_nullable
as int,timeout: null == timeout ? _self.timeout : timeout // ignore: cast_nullable_to_non_nullable
as int,lazy: null == lazy ? _self.lazy : lazy // ignore: cast_nullable_to_non_nullable
as bool,expectedStatus: null == expectedStatus ? _self.expectedStatus : expectedStatus // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
