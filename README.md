# fresh_grpc  🍋

[![coverage](https://github.com/amondnet/fresh_grpc/blob/main/coverage_badge.svg)](https://github.com/amondnet/fresh_grpc/actions)

---

A [grpc](https://pub.dev/packages/grpc) authenticator for built-in token refresh. Built to be used with [fresh](https://pub.dev/packages/fresh).


## Usage


```dart
import 'package:fresh_grpc/fresh_grpc.dart';

main() async {
  final channel = ClientChannel(
    'localhost',
    port: 50051,
    options: ChannelOptions(
      credentials: ChannelCredentials.insecure(),
      codecRegistry:
      CodecRegistry(codecs: const [GzipCodec(), IdentityCodec()]),
    ),
  );
  final fresh = FreshGrpc.oAuth2();
  final stub = GreeterClient(channel,options:fresh.toCallOptions());
  
  await fresh.retryUnary(stub.sayHello, HelloRequest()..name = 'world');
}
```

## Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

[tracker]: http://example.com/issues/replaceme
