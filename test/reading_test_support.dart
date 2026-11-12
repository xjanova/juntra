import 'dart:async';

import 'package:juntra/core/api/api_client.dart';

class RecordedCall {
  RecordedCall(this.path, this.data, this.key);
  final String path;
  final dynamic data;
  final String? key;
}

class ParityApi extends FakeApiClient {
  final calls = <RecordedCall>[];
  FutureOr<Map<String, dynamic>> Function(RecordedCall)? onPost;
  FutureOr<Map<String, dynamic>> Function(String)? onGet;

  @override
  Future<T> get<T>(String path, {Map<String, dynamic>? query}) async =>
      (await onGet!(path)) as T;

  @override
  Future<T> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? query,
    String? idempotencyKey,
  }) async {
    final call = RecordedCall(path, data, idempotencyKey);
    calls.add(call);
    return (await onPost!(call)) as T;
  }
}

class FakeApiClient implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
