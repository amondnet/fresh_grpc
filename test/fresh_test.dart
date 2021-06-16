import 'dart:async';

import 'package:fresh_grpc/fresh_grpc.dart';
import 'package:grpc/grpc.dart';
import 'package:http/http.dart' as $http;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'package:helloworld/helloworld.dart';

class MockTokenStorage<T> extends Mock implements TokenStorage<T> {}

class MockToken extends Mock implements OAuth2Token {}

class MockMetadata extends Mock implements Map<String, String> {}

class MockGrpcError extends Mock implements GrpcError {}

class MockGreeterClient extends Mock implements GreeterClient {}

class MockHttpClient extends Mock implements $http.Client {}

class MockResponseFuture<T> extends Mock implements ResponseFuture<T> {
  final Future<T> future;

  MockResponseFuture.value(T value) : future = Future.value(value);

  MockResponseFuture.error(Object error) : future = Future.error(error);

  MockResponseFuture.future(this.future);

  @override
  Future<S> then<S>(FutureOr<S> Function(T value) onValue,
          {Function? onError}) =>
      future.then(onValue, onError: onError);
}

Future<OAuth2Token> emptyRefreshToken(
    OAuth2Token? _, String? uri, $http.Client __) async {
  return MockToken();
}

Future<OAuth2Token> emptyObtainToken<T>($http.Client client, String uri) async {
  return MockToken();
}

void main() {
  group('Fresh', () {
    late TokenStorage<OAuth2Token> tokenStorage;
    late Map<String, String> metadata;
    late MockGreeterClient stub;
    final request = HelloRequest()..name = 'world';

    setUpAll(() {
      registerFallbackValue<OAuth2Token>(MockToken());
      registerFallbackValue<MockToken>(MockToken());
      registerFallbackValue<HelloRequest>(request);

      //registerFallbackValue<Options>(null);
      //registerFallbackValue<RequestOptions>(FakeRequestOptions());
      //registerFallbackValue<Response<dynamic>>(FakeResponse<dynamic>());
      //registerFallbackValue<DioError>(FakeDioError());
    });

    setUp(() {
      stub = MockGreeterClient();
      tokenStorage = MockTokenStorage<OAuth2Token>();
      metadata = MockMetadata();
    });

    group('configure token', () {
      group('setToken', () {
        test('invokes tokenStorage.write', () async {
          when(() => tokenStorage.read()).thenAnswer((_) async => MockToken());
          when(() => tokenStorage.write(any())).thenAnswer((_) async => null);
          final token = MockToken();
          final fresh = FreshGrpc.oAuth2(
              tokenStorage: tokenStorage,
              refreshToken: emptyRefreshToken,
              obtainToken: emptyObtainToken);
          await fresh.setToken(token);
          verify(() => tokenStorage.write(token)).called(1);
        });

        test('adds unauthenticated status when call setToken(null)', () async {
          when(() => tokenStorage.read()).thenAnswer((_) async => MockToken());
          when(() => tokenStorage.write(any())).thenAnswer((_) async => null);
          when(() => tokenStorage.delete()).thenAnswer((_) async => null);
          final fresh = FreshGrpc.oAuth2(
            tokenStorage: tokenStorage,
            refreshToken: emptyRefreshToken,
            obtainToken: emptyObtainToken,
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
    group('clearToken', () {
      test('adds unauthenticated status when call clearToken()', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => MockToken());
        when(() => tokenStorage.write(any())).thenAnswer((_) async => null);
        when(() => tokenStorage.delete()).thenAnswer((_) async => null);
        final fresh = FreshGrpc.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
          obtainToken: emptyObtainToken,
        );
        await fresh.clearToken();
        await expectLater(
          fresh.authenticationStatus,
          emitsInOrder(const <AuthenticationStatus>[
            AuthenticationStatus.unauthenticated,
          ]),
        );
      });
    });

    group('authenticate', () {
      const oAuth2Token = OAuth2Token(accessToken: 'accessToken');
      test(
          'appends token header when token is OAuth2Token '
          'and tokenHeader is not provided', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => oAuth2Token);
        when(() => tokenStorage.write(any())).thenAnswer((_) async => null);
        final fresh = FreshGrpc.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
          obtainToken: (_, __) async => (await tokenStorage.read())!,
        );

        await fresh.authenticate(metadata, '');
        final result = verify(() => metadata.addAll(captureAny()))..called(1);

        expect(
          (result.captured.first as Map<String, String>),
          {
            'Authorization': 'bearer accessToken',
          },
        );
      });

      test(
          'appends token header when token is OAuth2Token '
          'and tokenHeader is provided', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => oAuth2Token);
        when(() => tokenStorage.write(any())).thenAnswer((_) async => null);
        final fresh = FreshGrpc.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
          tokenHeader: (_) => {'custom-header': 'custom-token'},
          obtainToken: (_, __) async => (await tokenStorage.read())!,
        );

        await fresh.authenticate(metadata, '');
        final result = verify(() => metadata.addAll(captureAny()))..called(1);

        expect(
          (result.captured.first as Map<String, String>),
          {
            'custom-header': 'custom-token',
          },
        );
      });
      test(
          'appends the standard metadata when token use OAuth2Token constructor'
          'but tokenHeader is not provided', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => oAuth2Token);
        when(() => tokenStorage.write(any())).thenAnswer((_) async => null);
        final fresh = FreshGrpc.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
          obtainToken: (_, __) async => (await tokenStorage.read())!,
        );

        await fresh.authenticate(metadata, '');
        final result = verify(() => metadata.addAll(captureAny()))..called(1);

        expect(
          (result.captured.first as Map<String, String>),
          {
            'Authorization':
                '${oAuth2Token.tokenType} ${oAuth2Token.accessToken}',
          },
        );
      });
      test('returns error when token is null', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => null);
        when(() => tokenStorage.write(any())).thenAnswer((_) async => null);
        final error = MockGrpcError();
        final fresh = FreshGrpc.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
          obtainToken: (_, __) async => (await tokenStorage.read())!,
        );

        expect(
            () => fresh.authenticate(metadata, ''), throwsA(isA<GrpcError>()));
      });
    });

    group('retry', () {
      const oAuth2Token = OAuth2Token(accessToken: 'accessToken');

      test('should retry when unauthenticated error is occurred', () async {
        when(() => stub.sayHello(request)).thenAnswer((invocation) =>
            MockResponseFuture.error(GrpcError.unauthenticated('test')));

        when(() => tokenStorage.read()).thenAnswer((_) async => oAuth2Token);
        when(() => tokenStorage.write(any())).thenAnswer((_) async => null);
        final fresh = FreshGrpc.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
          obtainToken: (_, __) async => (await tokenStorage.read())!,
        );
        var retryCount = 0;

        try {
          await fresh.retryUnary(stub.sayHello, request,
              onRetry: (_) => retryCount++);
          fail('expect throw exception');
        } catch (e) {
          expect(e, isA<GrpcError>());
          final exception = e as GrpcError;
          expect(exception.code, StatusCode.unauthenticated);
          expect(retryCount > 0, isTrue);
        }
      });

      test('invokes refreshToken when token is not null', () async {
        var retryCount = 0;
        var refreshCallCount = 0;
        final token = MockToken();

        when(() => stub.sayHello(request, options: any(named: 'options')))
            .thenAnswer((invocation) => retryCount == 0
                ? MockResponseFuture.error(GrpcError.unauthenticated('test'))
                : MockResponseFuture.value(HelloReply()..message = 'hello'));
        when(() => tokenStorage.read()).thenAnswer((_) async => oAuth2Token);
        when(() => tokenStorage.write(any())).thenAnswer((_) async => null);
        final fresh = FreshGrpc.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: (_, __, ___) async {
            refreshCallCount++;
            return token;
          },
          obtainToken: (_, __) async => (await tokenStorage.read())!,
        );

        try {
          await fresh.retryUnary(stub.sayHello, request,
              onRetry: (_) => print('retry : ${++retryCount}'));
          expect(retryCount > 0, isTrue);
          expect(refreshCallCount, 1);
        } catch (e, s) {
          print('error :$e , $s');
          fail('expect success');
        }
      });
    });

    group('close', () {
      test('should close streams', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => null);
        when(() => tokenStorage.write(any())).thenAnswer((_) async => null);
        final fresh = FreshGrpc.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
          obtainToken: (_, __) async => (await tokenStorage.read())!,
        );

        final mockToken = MockToken();
        await fresh.setToken(mockToken);
        await fresh.close();

        await expectLater(
          fresh.authenticationStatus,
          emitsInOrder(<Matcher>[
            equals(AuthenticationStatus.authenticated),
            emitsDone,
          ]),
        );
      });
    });
  });
}
