import 'dart:async';

import 'package:fresh/fresh.dart';
import 'package:fresh_grpc/fresh_grpc.dart';
import 'package:grpc/grpc.dart' as $grpc;
import 'package:http/http.dart' as http;
import 'package:retry/retry.dart';

/// Signature for `shouldRefresh` on [Fresh].
typedef ShouldRefresh<T> = bool Function($grpc.GrpcError? error, T? token);

typedef RefreshToken<T> = Future<T> Function(
    T? token, String? uri, http.Client client);
typedef ObtainToken<T> = Future<T> Function(http.Client client, String uri);

/// {@template fresh}
/// A Grpc Authenticator for automatic token refresh.
/// Requires a concrete implementation of [TokenStorage], [ObtainToken] and [RefreshToken].
/// Handles transparently refreshing/caching tokens.
///
/// ```dart
///
/// ```
/// {@endtemplate}
class FreshGrpc<T> extends $grpc.BaseAuthenticator with FreshMixin<T> {
  FreshGrpc(
      {required TokenStorage<T> tokenStorage,
      required ObtainToken<T> obtainToken,
      required RefreshToken<T> refreshToken,
      ShouldRefresh<T>? shouldRefresh,
      TokenHeaderBuilder<T>? tokenHeader,
      RetryOptions retryOptions = const RetryOptions(
        delayFactor: Duration(milliseconds: 200),
        randomizationFactor: 0.25,
        maxDelay: Duration(seconds: 5),
        maxAttempts: 3,
      )})
      : _obtainToken = obtainToken,
        _refreshToken = refreshToken,
        _tokenHeader = tokenHeader,
        _shouldRefresh = shouldRefresh ?? _defaultShouldRefresh,
        _retryOptions = retryOptions {
    this.tokenStorage = tokenStorage;
  }

  static FreshGrpc<OAuth2Token> oAuth2({
    required TokenStorage<OAuth2Token> tokenStorage,
    required ObtainToken<OAuth2Token> obtainToken,
    required RefreshToken<OAuth2Token> refreshToken,
    ShouldRefresh<OAuth2Token>? shouldRefresh,
    TokenHeaderBuilder<OAuth2Token>? tokenHeader,
  }) {
    return FreshGrpc<OAuth2Token>(
      refreshToken: refreshToken,
      obtainToken: obtainToken,
      tokenStorage: tokenStorage,
      shouldRefresh: shouldRefresh,
      tokenHeader: tokenHeader ??
          (token) {
            return {
              'Authorization': '${token.tokenType} ${token.accessToken}',
            };
          },
    );
  }

  final ObtainToken<T> _obtainToken;
  final RefreshToken<T> _refreshToken;
  final TokenHeaderBuilder<T>? _tokenHeader;
  final ShouldRefresh<T> _shouldRefresh;
  final RetryOptions _retryOptions;
  String? _lastUri;
  Future<void>? _call;
  T? _accessToken;

  @override
  Future<void> obtainAccessCredentials(String uri) async {
    if (_call == null) {
      final authClient = http.Client();
      _call = _obtainToken(authClient, uri).then((credentials) async {
        await setToken(credentials);
        _call = null;
        authClient.close();
      });
    }
    return _call;
  }

  @override
  Future<void> authenticate(Map<String, String> metadata, String uri) async {
    _accessToken = await token;
    if (_accessToken == null || uri != _lastUri) {
      try {
        await obtainAccessCredentials(uri);
        _lastUri = uri;
        _accessToken = await token;
      } catch (e) {
        throw $grpc.GrpcError.unauthenticated('Require Authentication.');
      }
    }

    if (_accessToken == null) {
      throw $grpc.GrpcError.unauthenticated('Require Authentication.');
    }
    final tokenHeaders = _tokenHeader != null
        ? _tokenHeader!(_accessToken!)
        : const <String, String>{};

    metadata.addAll(tokenHeaders);

    if (_shouldRefresh(null, _accessToken!)) {
      // Token is about to expire. Extend it prematurely.
      final authClient = http.Client();
      unawaited(_refreshToken(_accessToken, _lastUri, authClient)
          .catchError((_) {})
          .then((refreshedToken) async {
        unawaited(setToken(refreshedToken));
      }).whenComplete(() => authClient.close()));
    }
  }

  /// Call [rpc] retrying so long as [_shouldRefresh] return `true` for the exception
  /// thrown.
  ///
  /// At every retry the [onRetry] function will be called (if given). The
  /// function [rpc] will be invoked at-most [this.attempts] times.
  Future<R> retryUnary<R, Q>(
      $grpc.ResponseFuture<R> Function(Q request, {$grpc.CallOptions? options})
          rpc,
      Q request,
      {Function(Exception)? onRetry,
      $grpc.CallOptions? options}) async {
    final client = http.Client();
    return _retryOptions.retry(
      () => rpc.call(request, options: options),
      retryIf: (e) {
        return e is $grpc.GrpcError &&
            e.code == $grpc.StatusCode.unauthenticated;
      },
      onRetry: (e) async {
        onRetry?.call(e);
        await _refreshToken(_accessToken, null, client);
      },
    ).whenComplete(() => client.close());
  }

  static bool _defaultShouldRefresh($grpc.GrpcError? error, dynamic token) {
    return error?.code == $grpc.StatusCode.unauthenticated;
  }
}

Future<R> retryUnary<R, Q>(
  $grpc.ResponseFuture<R> Function(Q request, {$grpc.CallOptions? options}) rpc,
  Q request, {
  Function(Exception)? onRetry,
  Duration delayFactor = const Duration(milliseconds: 200),
  double randomizationFactor = 0.25,
  Duration maxDelay = const Duration(seconds: 5),
  int maxAttempts = 5,
}) async {
  final response = await retry<R>(
    () => rpc.call(request),
    retryIf: (e) {
      return e is $grpc.GrpcError && e.code == $grpc.StatusCode.unauthenticated;
    },
    onRetry: onRetry,
    delayFactor: delayFactor,
    randomizationFactor: randomizationFactor,
    maxDelay: maxDelay,
    maxAttempts: maxAttempts,
  );

  return response;
}
