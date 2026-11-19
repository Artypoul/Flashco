import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flashco/common/common.dart';
import 'package:flashco/enum/enum.dart';
import 'package:flashco/state.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

class Request {
  late final Dio dio;
  late final Dio _clashDio;
  late final Dio releaseDio;
  String? userAgent;

  ProviderReader? _read;

  void attach(ProviderReader read) {
    _read = read;
  }

  Request() {
    dio = Dio(BaseOptions(headers: {'User-Agent': browserUa}));
    releaseDio = Dio(BaseOptions(headers: {'User-Agent': browserUa}));
    releaseDio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        // HttpOverrides may relax verification for subscriptions; releases never do.
        client.badCertificateCallback = null;
        return client;
      },
    );
    _clashDio = Dio();
    _clashDio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.findProxy = (Uri uri) {
          client.userAgent = globalState.ua;
          final read = _read;
          if (read == null) {
            return 'DIRECT';
          }
          return FlashcoHttpOverrides.findProxyForReader(read, uri);
        };
        return client;
      },
    );
  }

  Future<Response<T>> _download<T>(String url, ResponseType responseType) {
    final target = downloadTarget(url);
    final cancelToken = CancelToken();
    return _clashDio
        .getUri<T>(
          target.uri,
          options: Options(responseType: responseType, headers: target.headers),
          cancelToken: cancelToken,
        )
        .timeout(
          downloadTimeoutDuration,
          onTimeout: () {
            cancelToken.cancel();
            throw DioException.receiveTimeout(
              timeout: downloadTimeoutDuration,
              requestOptions: RequestOptions(path: url),
            );
          },
        );
  }

  Future<Response<Uint8List>> getFileResponseForUrl(String url) async {
    try {
      return await _download<Uint8List>(url, ResponseType.bytes);
    } catch (e) {
      commonPrint.log(
        'getFileResponseForUrl error ${compactError(e)}',
        logLevel: LogLevel.warning,
      );
      rethrow;
    }
  }

  Future<Response<String>> getTextResponseForUrl(String url) async {
    try {
      return await _download<String>(url, ResponseType.plain);
    } catch (e) {
      commonPrint.log(
        'getTextResponseForUrl error ${compactError(e)}',
        logLevel: LogLevel.warning,
      );
      rethrow;
    }
  }

  Future<String> downloadVerifiedRelease({
    required String tag,
    required String name,
    required String directory,
    required CancelToken cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    final path = '$directory${Platform.pathSeparator}$name';
    final file = File(path);
    try {
      final sums = await releaseDio.getUri<String>(
        releaseAssetUri(tag, releaseChecksumsName),
        options: Options(responseType: ResponseType.plain),
        cancelToken: cancelToken,
      );
      _requireHttpsRedirects(sums);
      final expected = releaseChecksum(sums.data ?? '', name);
      if (expected == null) throw ReleaseNotVerifiedException(name);
      final response = await releaseDio.downloadUri(
        releaseAssetUri(tag, name),
        path,
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
      );
      _requireHttpsRedirects(response);
      if (cancelToken.isCancelled || await fileSha256(path) != expected) {
        if (cancelToken.isCancelled) throw cancelToken.cancelError!;
        throw ReleaseNotVerifiedException(name);
      }
      return path;
    } catch (_) {
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  void _requireHttpsRedirects(Response<dynamic> response) {
    if (response.realUri.scheme != 'https' ||
        response.redirects.any(
          (redirect) =>
              redirect.location.hasScheme &&
              redirect.location.scheme != 'https',
        )) {
      throw const FormatException('Insecure release redirect');
    }
  }

  /// Null when this build is current; throws when GitHub cannot be asked.
  Future<Map<String, dynamic>?> checkForUpdate() async {
    final release = await latestRelease();
    final remoteVersion = release['tag_name'] as String;
    final version = globalState.packageInfo.version;
    final hasUpdate =
        compareVersions(remoteVersion.replaceAll('v', ''), version) > 0;
    return hasUpdate ? release : null;
  }

  /// The release page redirect still answers once the hourly API quota is spent.
  Future<Map<String, dynamic>> latestRelease() async {
    try {
      final response = await releaseDio.get<Map<String, dynamic>>(
        'https://api.github.com/repos/$repository/releases/latest',
        options: Options(responseType: ResponseType.json),
      );
      _requireHttpsRedirects(response);
      return response.data!;
    } on DioException catch (error) {
      commonPrint.log(
        'latest release API failed: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
    }
    final response = await releaseDio.get<void>(
      'https://github.com/$repository/releases/latest',
      options: Options(
        followRedirects: false,
        validateStatus: (status) => status != null && status < 400,
      ),
    );
    final location = response.headers.value(HttpHeaders.locationHeader);
    final segments = Uri.tryParse(location ?? '')?.pathSegments ?? const [];
    final tagIndex = segments.indexOf('tag') + 1;
    if (tagIndex == 0 || tagIndex >= segments.length) {
      throw FormatException('No release tag in the redirect', location);
    }
    return {'tag_name': segments[tagIndex]};
  }
}

final request = Request();

/// Some subscription servers send a gzip or zlib body without saying so in
/// Content-Encoding, which is the only signal dart:io decompresses on.
Uint8List decompressUnlabeled(Uint8List bytes) {
  final codec = switch (bytes) {
    [0x1f, 0x8b, ...] => gzip,
    [0x78, final flags, ...] when (0x78 << 8 | flags) % 31 == 0 => zlib,
    _ => null,
  };
  if (codec == null) {
    return bytes;
  }
  try {
    return Uint8List.fromList(codec.decode(bytes));
  } on FormatException {
    return bytes;
  }
}

/// dart:io turns [Uri.userInfo] into Basic credentials still percent-encoded.
@visibleForTesting
({Uri uri, Map<String, Object> headers}) downloadTarget(String url) {
  final uri = url.webUri ?? Uri.parse(url);
  if (uri.userInfo.isEmpty) {
    return (uri: uri, headers: const {});
  }
  final credentials = uri.userInfo.split(':').map(_decodeUserInfo).join(':');
  return (
    uri: uri.replace(userInfo: ''),
    headers: {
      HttpHeaders.authorizationHeader:
          'Basic ${base64.encode(utf8.encode(credentials))}',
    },
  );
}

String _decodeUserInfo(String value) {
  try {
    return Uri.decodeComponent(value);
  } on ArgumentError {
    return value;
  }
}

String? getFileNameForDisposition(String? disposition) {
  if (disposition == null) return null;
  final parseValue = HeaderValue.parse(disposition);
  final parameters = parseValue.parameters;
  final fileNamePointKey = parameters.keys.firstWhere(
    (key) => key == 'filename*',
    orElse: () => '',
  );
  if (fileNamePointKey.isNotEmpty) {
    final res = parameters[fileNamePointKey]?.split("''") ?? [];
    if (res.length >= 2) {
      return Uri.decodeComponent(res[1]);
    }
  }
  final fileNameKey = parameters.keys.firstWhere(
    (key) => key == 'filename',
    orElse: () => '',
  );
  if (fileNameKey.isEmpty) return null;
  return parameters[fileNameKey];
}
