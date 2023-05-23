import "dart:async";
import "dart:convert";
import "dart:io";
import "package:dart_openai/src/core/utils/http_client_web.dart"
    if (dart.library.io) "package:dart_openai/src/core/utils/http_client_io.dart";
import "package:dart_openai/openai.dart";
import "package:dart_openai/src/core/builder/headers.dart";
import "package:dart_openai/src/core/utils/logger.dart";
import "package:dio/dio.dart";
import "package:http/http.dart" as http;
import "package:meta/meta.dart";

import '../constants/strings.dart';
import '../exceptions/request_failure.dart';

/// Handling exceptions returned by OpenAI Stream API.
final class _OpenAIChatStreamSink implements EventSink<String> {
  final EventSink<String> _sink;

  final List<String> _carries = [];

  _OpenAIChatStreamSink(this._sink);

  void add(String str) {
    final isStartOfResponse = str.startsWith(OpenAIStrings.streamResponseStart);
    final isEndOfResponse = str.contains(OpenAIStrings.streamResponseEnd);
    final isDataResponseBoundaries = isStartOfResponse || isEndOfResponse;

    if (isDataResponseBoundaries) {
      addCarryIfNeeded();

      _sink.add(str);
    } else {
      _carries.add(str);
    }
  }

  void addError(Object error, [StackTrace? stackTrace]) {
    _sink.addError(error, stackTrace);
  }

  void addSlice(String str, int start, int end, bool isLast) {
    if (start == 0 && end == str.length) {
      add(str);
    } else {
      add(str.substring(start, end));
    }

    if (isLast) close();
  }

  void addCarryIfNeeded() {
    if (_carries.isNotEmpty) {
      _sink.add(_carries.join());

      _carries.clear();
    }
  }

  void close() {
    addCarryIfNeeded();
    _sink.close();
  }
}

// class OpenAIChatStreamLineSplitter extends LineSplitter {
//   const OpenAIChatStreamLineSplitter();

//   Stream<String> bind(Stream<String> stream) {
//     Stream<String> lineStream = super.bind(stream);

//     return Stream<String>.eventTransformed(
//       lineStream,
//       (sink) => _OpenAIChatStreamSink(sink),
//     );
//   }
// }

const openAIChatStreamLineSplitter = const LineSplitter();

@protected
@immutable
abstract final class OpenAINetworkingClient {
  static Future<T> get<T>({
    required String from,
    bool returnRawResponse = false,
    T Function(Map<String, dynamic>)? onSuccess,
  }) async {
    OpenAILogger.logStartRequest(from);

    final uri = Uri.parse(from);
    final headers = HeadersBuilder.build();

    final client = createClient();

    final response = await client.get(uri, headers: headers);

    if (returnRawResponse) {
      return response.body as T;
    }

    OpenAILogger.requestToWithStatusCode(from, response.statusCode);
    OpenAILogger.startingDecoding();

    final utf8decoder = Utf8Decoder();

    final convertedBody = utf8decoder.convert(response.bodyBytes);
    final Map<String, dynamic> decodedBody = decodeToMap(convertedBody);

    OpenAILogger.decodedSuccessfully();

    if (doesErrorExists(decodedBody)) {
      final Map<String, dynamic> error =
          decodedBody[OpenAIStrings.errorFieldKey];
      final message = error[OpenAIStrings.messageFieldKey];
      final statusCode = response.statusCode;

      final exception = RequestFailedException(message, statusCode);
      OpenAILogger.errorOcurred(exception);

      throw exception;
    } else {
      OpenAILogger.requestFinishedSuccessfully();

      return onSuccess!(decodedBody);
    }
  }

  static Stream<T> getStream<T>({
    required String from,
    required T Function(Map<String, dynamic>) onSuccess,
  }) {
    final controller = StreamController<T>();

    final client = createClient();
    final uri = Uri.parse(from);

    final httpMethod = OpenAIStrings.getMethod;

    final request = http.Request(httpMethod, uri);

    request.headers.addAll(HeadersBuilder.build());

    Future<void> close() {
      return Future.wait([
        Future.delayed(Duration.zero, client.close),
        controller.close(),
      ]);
    }

    client.send(request).then((streamedResponse) {
      streamedResponse.stream.listen(
        (value) {
          final data = utf8.decode(value);

          final dataLines = openAIChatStreamLineSplitter
              .convert(data)
              .where((element) => element.isNotEmpty)
              .toList();

          for (String line in dataLines) {
            if (line.startsWith(OpenAIStrings.streamResponseStart)) {
              final String data = line.substring(6);
              if (data.startsWith(OpenAIStrings.streamResponseEnd)) {
                OpenAILogger.streamResponseDone();

                return;
              }

              final decoded = decodeToMap(data);
              controller.add(onSuccess(decoded));
            }
          }
        },
        onDone: () {
          close();
        },
        onError: (err) {
          controller.addError(err);
        },
      );
    });

    return controller.stream;
  }

  static Future<T> post<T>({
    required String to,
    required T Function(Map<String, dynamic>) onSuccess,
    Map<String, dynamic>? body,
  }) async {
    OpenAILogger.logStartRequest(to);

    final uri = Uri.parse(to);
    final headers = HeadersBuilder.build();
    final handledBody = body != null ? jsonEncode(body) : null;
    final client = createClient();

    final response =
        await client.post(uri, headers: headers, body: handledBody);

    OpenAILogger.requestToWithStatusCode(to, response.statusCode);

    OpenAILogger.startingDecoding();

    Utf8Decoder utf8decoder = Utf8Decoder();

    final convertedBody = utf8decoder.convert(response.bodyBytes);

    final Map<String, dynamic> decodedBody = decodeToMap(convertedBody);

    OpenAILogger.decodedSuccessfully();

    if (doesErrorExists(decodedBody)) {
      final Map<String, dynamic> error =
          decodedBody[OpenAIStrings.errorFieldKey];
      final message = error[OpenAIStrings.messageFieldKey];
      final statusCode = response.statusCode;

      final exception = RequestFailedException(message, statusCode);
      OpenAILogger.errorOcurred(exception);

      throw exception;
    } else {
      OpenAILogger.requestFinishedSuccessfully();

      return onSuccess(decodedBody);
    }
  }

  static Stream<T> postStream<T>({
    required String to,
    required T Function(Map<String, dynamic>) onSuccess,
    required Map<String, dynamic> body,
  }) {
    final controller = StreamController<T>();

    try {
      final client = createDio();

      final headers = HeadersBuilder.build();
      Future<void> close() {
        return Future.wait([
          Future.delayed(Duration.zero, client.close),
          controller.close(),
        ]);
      }

      final options =
          Options(headers: headers, responseType: ResponseType.stream);

      OpenAILogger.logStartRequest(to);

      client.post(to, data: body, options: options).then(
        (respond) {
          OpenAILogger.startReadStreamResponse();
          final body = respond.data as ResponseBody;
          final statusCode = respond.statusCode ?? 200;
          if (statusCode != 200) {
            final exception = RequestFailedException(
                "Request failed with status code $statusCode", statusCode);
            OpenAILogger.errorOcurred(exception);
            controller.addError(exception);

            return;
          }
          body.stream.listen(
            (value) {
              final data = utf8.decode(value, allowMalformed: true);

              final dataLines = data
                  .split("\n")
                  .where((element) => element.isNotEmpty)
                  .toList();

              for (String line in dataLines) {
                if (line.startsWith(OpenAIStrings.streamResponseStart)) {
                  final String data = line.substring(6);
                  if (data.contains(OpenAIStrings.streamResponseEnd)) {
                    OpenAILogger.streamResponseDone();

                    return;
                  }

                  final decoded = jsonDecode(data) as Map<String, dynamic>;

                  controller.add(onSuccess(decoded));

                  continue;
                }

                final decodedData = decodeToMap(data);

                if (doesErrorExists(decodedData)) {
                  final error = decodedData[OpenAIStrings.errorFieldKey]
                      as Map<String, dynamic>;
                  final message = error[OpenAIStrings.messageFieldKey];
                  final exception = RequestFailedException(message, statusCode);

                  controller.addError(exception);
                }
              }
            },
            onDone: () {
              close();
            },
            onError: (err) {
              controller.addError(err);
            },
          );
        },
        onError: (error, stackTrace) {
          controller.addError(error, stackTrace);
        },
      );
    } catch (e) {
      controller.addError(e);
    }

    return controller.stream;
  }

  static Future imageEditForm<T>({
    required String to,
    required T Function(Map<String, dynamic>) onSuccess,
    required File image,
    required File? mask,
    required Map<String, String> body,
  }) async {
    OpenAILogger.logStartRequest(to);

    final uri = Uri.parse(to);

    final headers = HeadersBuilder.build();

    final httpMethod = OpenAIStrings.postMethod;

    final request = http.MultipartRequest(httpMethod, uri);

    request.headers.addAll(headers);

    final file = await http.MultipartFile.fromPath("image", image.path);

    final maskFile = mask != null
        ? await http.MultipartFile.fromPath("mask", mask.path)
        : null;

    request.files.add(file);

    if (maskFile != null) request.files.add(maskFile);

    request.fields.addAll(body);

    final client = createClient();

    final http.StreamedResponse response = await client.send(request);

    OpenAILogger.requestToWithStatusCode(to, response.statusCode);

    OpenAILogger.startingDecoding();

    final String encodedBody = await response.stream.bytesToString();

    final Map<String, dynamic> decodedBody = decodeToMap(encodedBody);

    OpenAILogger.decodedSuccessfully();

    if (doesErrorExists(decodedBody)) {
      final Map<String, dynamic> error =
          decodedBody[OpenAIStrings.errorFieldKey];

      final message = error[OpenAIStrings.messageFieldKey];
      final statusCode = response.statusCode;

      final exception = RequestFailedException(message, statusCode);
      OpenAILogger.errorOcurred(exception);

      throw exception;
    } else {
      OpenAILogger.requestFinishedSuccessfully();

      return onSuccess(decodedBody);
    }
  }

  static Future<T> imageVariationForm<T>({
    required String to,
    required T Function(Map<String, dynamic>) onSuccess,
    // ignore: avoid-unused-parameters
    required Map<String, dynamic> body,
    required File image,
  }) async {
    OpenAILogger.logStartRequest(to);

    final httpMethod = OpenAIStrings.postMethod;

    final request = http.MultipartRequest(httpMethod, Uri.parse(to));

    request.headers.addAll(HeadersBuilder.build());

    final imageFile = await http.MultipartFile.fromPath("image", image.path);

    request.files.add(imageFile);

    final client = createClient();

    final http.StreamedResponse response = await client.send(request);

    OpenAILogger.requestToWithStatusCode(to, response.statusCode);

    OpenAILogger.startingDecoding();

    final String encodedBody = await response.stream.bytesToString();

    final Map<String, dynamic> decodedBody = decodeToMap(encodedBody);

    OpenAILogger.decodedSuccessfully();

    if (doesErrorExists(decodedBody)) {
      final Map<String, dynamic> error =
          decodedBody[OpenAIStrings.errorFieldKey];
      final message = error[OpenAIStrings.messageFieldKey];
      final statusCode = response.statusCode;

      final exception = RequestFailedException(message, statusCode);
      OpenAILogger.errorOcurred(exception);

      throw exception;
    } else {
      OpenAILogger.requestFinishedSuccessfully();

      return onSuccess(decodedBody);
    }
  }

  static Future<T> fileUpload<T>({
    required String to,
    required T Function(Map<String, dynamic>) onSuccess,
    required Map<String, String> body,
    required File file,
  }) async {
    OpenAILogger.logStartRequest(to);

    final uri = Uri.parse(to);
    final headers = HeadersBuilder.build();

    final httpMethod = OpenAIStrings.postMethod;
    final request = http.MultipartRequest(httpMethod, uri);

    request.headers.addAll(headers);

    final multiPartFile = await http.MultipartFile.fromPath("file", file.path);

    request.files.add(multiPartFile);
    request.fields.addAll(body);

    final client = createClient();

    final http.StreamedResponse response = await client.send(request);

    OpenAILogger.requestToWithStatusCode(to, response.statusCode);

    OpenAILogger.startingDecoding();

    final String encodedBody = await response.stream.bytesToString();
    final Map<String, dynamic> decodedBody = decodeToMap(encodedBody);

    OpenAILogger.decodedSuccessfully();
    if (doesErrorExists(decodedBody)) {
      final Map<String, dynamic> error =
          decodedBody[OpenAIStrings.errorFieldKey];
      final message = error[OpenAIStrings.messageFieldKey];
      final statusCode = response.statusCode;

      final exception = RequestFailedException(message, statusCode);
      OpenAILogger.errorOcurred(exception);

      throw exception;
    } else {
      OpenAILogger.requestFinishedSuccessfully();

      return onSuccess(decodedBody);
    }
  }

  static Future<T> delete<T>({
    required String from,
    required T Function(Map<String, dynamic> response) onSuccess,
  }) async {
    OpenAILogger.logStartRequest(from);

    final headers = HeadersBuilder.build();
    final uri = Uri.parse(from);

    final client = createClient();

    final response = await client.delete(uri, headers: headers);

    OpenAILogger.requestToWithStatusCode(from, response.statusCode);

    OpenAILogger.startingDecoding();

    final Map<String, dynamic> decodedBody = decodeToMap(response.body);

    OpenAILogger.decodedSuccessfully();

    if (doesErrorExists(decodedBody)) {
      final Map<String, dynamic> error =
          decodedBody[OpenAIStrings.errorFieldKey];
      final String message = error[OpenAIStrings.messageFieldKey];
      final statusCode = response.statusCode;

      final exception = RequestFailedException(message, statusCode);
      OpenAILogger.errorOcurred(exception);

      throw exception;
    } else {
      OpenAILogger.requestFinishedSuccessfully();

      return onSuccess(decodedBody);
    }
  }

  static Map<String, dynamic> decodeToMap(String responseBody) {
    return jsonDecode(responseBody) as Map<String, dynamic>;
  }

  static bool doesErrorExists(Map<String, dynamic> decodedResponseBody) {
    return decodedResponseBody[OpenAIStrings.errorFieldKey] != null;
  }
}
