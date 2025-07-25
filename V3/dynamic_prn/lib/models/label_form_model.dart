// models/label_form_model.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class LabelFormModel {
  final String name;
  final String rawPrn;
  final Map<String, String> titleData; // title → value
  final Map<String, String> originalPrnValues; // title → original PRN value
  final List<String> barcodeTitles;
  final String barcodeSeparator;
  final String? scaleInputTitle; // This is the field in question

  LabelFormModel({
    required this.name,
    required this.rawPrn,
    required this.titleData,
    required this.originalPrnValues,
    required this.barcodeTitles,
    required this.barcodeSeparator,
    this.scaleInputTitle, // Make sure this is in your constructor
  });

  // Method to create a copy with updated values
  LabelFormModel copyWith({
    String? name,
    String? rawPrn,
    Map<String, String>? titleData,
    Map<String, String>? originalPrnValues,
    List<String>? barcodeTitles,
    String? barcodeSeparator,
    String? scaleInputTitle, // Ensure copyWith handles this
  }) {
    return LabelFormModel(
      name: name ?? this.name,
      rawPrn: rawPrn ?? this.rawPrn,
      titleData: titleData ?? this.titleData,
      originalPrnValues: originalPrnValues ?? this.originalPrnValues,
      barcodeTitles: barcodeTitles ?? this.barcodeTitles,
      barcodeSeparator: barcodeSeparator ?? this.barcodeSeparator,
      scaleInputTitle: scaleInputTitle ?? this.scaleInputTitle,
    );
  }

  // --- JSON serialization/deserialization methods ---
  Map<String, dynamic> toJson() => {
    'name': name,
    'rawPrn': rawPrn,
    'titleData': titleData,
    'originalPrnValues': originalPrnValues,
    'barcodeTitles': barcodeTitles,
    'barcodeSeparator': barcodeSeparator,
    'scaleInputTitle': scaleInputTitle, // Ensure this is serialized
  };

  factory LabelFormModel.fromJson(Map<String, dynamic> json) => LabelFormModel(
    name: json['name'] as String,
    rawPrn: json['rawPrn'] as String,
    titleData: Map<String, String>.from(json['titleData'] as Map),
    originalPrnValues: Map<String, String>.from(json['originalPrnValues'] as Map),
    barcodeTitles: List<String>.from(json['barcodeTitles'] as List),
    barcodeSeparator: json['barcodeSeparator'] as String,
    scaleInputTitle: json['scaleInputTitle'] as String?, // Ensure this is deserialized as String?
  );

  // --- File Storage Methods ---
  static Future<String> _localPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  static Future<File> _localFile(String name) async {
    final path = await _localPath();
    return File('$path/form_model_${name.replaceAll(RegExp(r'[^\w\s]+'), '_')}.json');
  }

  static Future<void> save(LabelFormModel model) async {
    final file = await _localFile(model.name);
    final String jsonString = jsonEncode(model.toJson());
    await file.writeAsString(jsonString);

    // Also update SharedPreferences for last used template
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_used_template_name', model.name);
    print('LabelFormModel: Saved model "${model.name}" and set as last used.');
  }

  static Future<LabelFormModel?> load(String name) async {
    try {
      final file = await _localFile(name);
      if (!await file.exists()) {
        print('LabelFormModel: File for model "$name" not found.');
        return null;
      }
      final String jsonString = await file.readAsString();
      final Map<String, dynamic> jsonMap = jsonDecode(jsonString);
      final loadedModel = LabelFormModel.fromJson(jsonMap);
      print('LabelFormModel: Loaded model "${loadedModel.name}" successfully. ScaleInputTitle: ${loadedModel.scaleInputTitle}');
      return loadedModel;
    } catch (e) {
      print('LabelFormModel: Error loading model "$name": $e');
      return null;
    }
  }

  static Future<void> delete(String name) async {
    try {
      final file = await _localFile(name);
      if (await file.exists()) {
        await file.delete();
        print('LabelFormModel: Deleted model file for "$name".');

        // If the deleted model was the last used, clear the preference
        final prefs = await SharedPreferences.getInstance();
        final lastUsedName = prefs.getString('last_used_template_name');
        if (lastUsedName == name) {
          await prefs.remove('last_used_template_name');
          print('LabelFormModel: Cleared last_used_template_name preference.');
        }
      } else {
        print('LabelFormModel: No file found to delete for "$name".');
      }
    } catch (e) {
      print('LabelFormModel: Error deleting model "$name": $e');
    }
  }
}