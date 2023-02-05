import 'package:collection/collection.dart';
import 'sub_models/choice.dart';
import 'sub_models/usage.dart';

export 'sub_models/choice.dart';
export 'sub_models/usage.dart';
export 'stream/completion.dart';

class OpenAICompletionModel {
  /// The ID of the completion.
  String id;

  /// The date the completion was created.
  DateTime created;

  /// The model used to generate the completion.
  String model;

  /// The choices generated by the completion.
  List<OpenAICompletionModelChoice> choices;

  /// The usage of the completion, if any.
  OpenAICompletionModelUsage? usage;

  /// This class is used to represent an OpenAI completion.
  OpenAICompletionModel({
    required this.id,
    required this.created,
    required this.model,
    required this.choices,
    required this.usage,
  });

  /// This method is used to convert a [Map<String, dynamic>] object to a [OpenAICompletionModel] object.
  factory OpenAICompletionModel.fromJson(Map<String, dynamic> json) {
    return OpenAICompletionModel(
      id: json['id'],
      created: DateTime.fromMillisecondsSinceEpoch(json['created'] * 1000),
      model: json['model'],
      choices: (json['choices'] as List<dynamic>)
          .map((i) => OpenAICompletionModelChoice.fromJson(i))
          .toList(),
      usage: OpenAICompletionModelUsage.fromJson(json['usage']),
    );
  }

  @override
  String toString() {
    return 'OpenAICompletionModel(id: $id, created: $created, model: $model, choices: $choices)';
  }

  @override
  bool operator ==(covariant OpenAICompletionModel other) {
    if (identical(this, other)) return true;
    final listEquals = const DeepCollectionEquality().equals;

    return other.id == id &&
        other.created == created &&
        other.model == model &&
        listEquals(other.choices, choices);
  }

  @override
  int get hashCode {
    return id.hashCode ^ created.hashCode ^ model.hashCode ^ choices.hashCode;
  }
}
