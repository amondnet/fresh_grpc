import 'package:fresh/fresh.dart';
import 'package:fresh_grpc/fresh_grpc.dart';
import 'package:grpc/grpc.dart';
import 'package:http/http.dart' as http;
import 'package:pedantic/pedantic.dart' show unawaited;

typedef ShouldRefresh<T> = bool Function(T token);

typedef RefreshToken<T> = Future<T> Function(T? token, String? uri);
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
class FreshGrpc<T> extends BaseAuthenticator with FreshMixin<T> {
  FreshGrpc({
    required TokenStorage<T> tokenStorage,
    required ObtainToken<T> obtainToken,
    required RefreshToken<T> refreshToken,
    required ShouldRefresh<T> shouldRefresh,
    TokenHeaderBuilder<T>? tokenHeader,
  })  : _obtainToken = obtainToken,
        _refreshToken = refreshToken,
        _tokenHeader = tokenHeader,
        _shouldRefresh = shouldRefresh {
    this.tokenStorage = tokenStorage;
  }

  static FreshGrpc<OAuth2Token> oAuth2({
    required TokenStorage<OAuth2Token> tokenStorage,
    required ObtainToken<OAuth2Token> obtainToken,
    required RefreshToken<OAuth2Token> refreshToken,
    required ShouldRefresh<OAuth2Token> shouldRefresh,
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

  String? _lastUri;
  Future<void>? _call;

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
    final currentToken = await token;
    if (currentToken == null || uri != _lastUri) {
      await obtainAccessCredentials(uri);
      _lastUri = uri;
    }

    if (currentToken == null) {
      throw GrpcError.unauthenticated('Require Authentication.');
    }
    final tokenHeaders = _tokenHeader != null
        ? _tokenHeader!(currentToken)
        : const <String, String>{};

    metadata.addAll(tokenHeaders);

    if (_shouldRefresh(currentToken)) {
      // Token is about to expire. Extend it prematurely.
      unawaited(_refreshToken(currentToken, _lastUri)
          .catchError((_) {})
          .then((refreshedToken) async {
        unawaited(setToken(refreshedToken));
      }));
    }
  }
}

class GrpcServiceWrapper {}
