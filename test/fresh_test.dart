import 'package:fresh_grpc/fresh_grpc.dart';

//import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

class MockTokenStorage<T> extends Mock implements TokenStorage<T> {}

class MockOAuth2Token extends Mock implements OAuth2Token {}

class MockToken extends Mock implements OAuth2Token {}

Future<T?> emptyRefreshToken<T>(dynamic _, dynamic __) async => null;

Future<T?> emptyObtainToken<T>(dynamic _, dynamic __) async => null;

void main() {
  group('Fresh', () {
    late TokenStorage<OAuth2Token> tokenStorage;

    setUpAll(() {
      registerFallbackValue<OAuth2Token>(MockToken());
      registerFallbackValue<MockToken>(MockToken());
      //registerFallbackValue<Options>(null);
      //registerFallbackValue<RequestOptions>(FakeRequestOptions());
      //registerFallbackValue<Response<dynamic>>(FakeResponse<dynamic>());
      //registerFallbackValue<DioError>(FakeDioError());
    });

    setUp(() {
      tokenStorage = MockTokenStorage<OAuth2Token>();
    });

    group('configure token', () {
      group('setToken', () {
        test('invokes tokenStorage.write', () async {
          when(() => tokenStorage.read()).thenAnswer((_) async => MockToken());
          when(() => tokenStorage.write(any())).thenAnswer((_) async => null);
          final token = MockToken();
          final fresh = FreshGrpc.oAuth2(
              tokenStorage: tokenStorage,
              refreshToken: emptyRefreshToken as Future<OAuth2Token> Function(OAuth2Token, String?),
              obtainToken: emptyObtainToken as Future<OAuth2Token> Function(Client, String));
          await fresh.setToken(token);
          verify(() => tokenStorage.write(token)).called(1);
        });

        test('adds unauthenticated status when call setToken(null)', () async {
          when(() => tokenStorage.read()).thenAnswer((_) async => MockToken());
          when(() => tokenStorage.write(any())).thenAnswer((_) async => null);
          when(() => tokenStorage.delete()).thenAnswer((_) async => null);
          final fresh = FreshGrpc.oAuth2(
            tokenStorage: tokenStorage,
            refreshToken: emptyRefreshToken as Future<OAuth2Token> Function(OAuth2Token, String?),
          );
          await fresh.setToken(null);
          await expectLater(
            fresh.authenticationStatus,
            emitsInOrder(const <AuthenticationStatus>[
              AuthenticationStatus.unauthenticated,
            ]),
          );
        });
      });
    });
  });
}
