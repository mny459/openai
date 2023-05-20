import 'dart:io';

import 'package:dart_openai/src/instance/openai.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

http.Client createClient() {
  http.Client client;

  final proxy = OpenAI.proxy;
  // Set Proxy
  if (proxy != null && proxy.isNotEmpty) {
    final c = HttpClient();
    c.findProxy = (uri) {
      return 'PROXY $proxy';
    };
    client = IOClient(c);
  } else {
    client = http.Client();
  }

  return client;
}
