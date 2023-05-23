import 'package:dart_openai/openai.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fetch_client/fetch_client.dart' as fetch;

fetch.FetchClient createClient() =>
    fetch.FetchClient(mode: fetch.RequestMode.cors);

Dio createDio() {
  final dio = Dio();

  // Weather set proxy
  final proxy = OpenAI.proxy;
  if (proxy != null && proxy.isNotEmpty) {
    dio.httpClientAdapter = IOHttpClientAdapter()
      ..onHttpClientCreate = (client) {
        client.findProxy = (uri) {
          return 'PROXY $proxy';
        };

        return client;
      };
  }

  return dio;
}