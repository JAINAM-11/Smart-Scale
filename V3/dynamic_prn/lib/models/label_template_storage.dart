import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/label_template.dart';

class LabelTemplateStorage {
  static const String _key = 'label_templates';

  static Future<void> saveTemplate(LabelTemplate template) async {
    print('LabelTemplateStorage: Attempting to save template: ${template.name}'); // DEBUG
    final prefs = await SharedPreferences.getInstance();
    final List<String> existing = prefs.getStringList(_key) ?? [];

    existing.removeWhere((s) {
      final existingTemplate = LabelTemplate.fromJson(jsonDecode(s));
      final isMatch = existingTemplate.name == template.name;
      if (isMatch) {
        print('LabelTemplateStorage: Removing existing template with same name: ${template.name}'); // DEBUG
      }
      return isMatch;
    });

    existing.add(jsonEncode(template.toJson()));
    await prefs.setStringList(_key, existing);
    print('LabelTemplateStorage: Successfully saved template: ${template.name}'); // DEBUG
  }

  static Future<List<LabelTemplate>> loadTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> stored = prefs.getStringList(_key) ?? [];
    final List<LabelTemplate> templates = stored.map((e) => LabelTemplate.fromJson(jsonDecode(e))).toList();
    print('LabelTemplateStorage: Loaded ${templates.length} templates.'); // DEBUG
    if (templates.isEmpty) {
      print('LabelTemplateStorage: No templates found for key "$_key".'); // DEBUG
    } else {
      for (var t in templates) {
        print('  - Loaded template: ${t.name}'); // DEBUG
      }
    }
    return templates;
  }

  /// Deletes a template with the given [name] from storage.
  static Future<void> deleteTemplate(String name) async {
    print('LabelTemplateStorage: Attempting to delete template: $name'); // DEBUG
    final prefs = await SharedPreferences.getInstance();
    final List<String> existing = prefs.getStringList(_key) ?? [];

    final initialLength = existing.length;
    existing.removeWhere((s) => LabelTemplate.fromJson(jsonDecode(s)).name == name);

    if (existing.length < initialLength) {
      await prefs.setStringList(_key, existing);
      print('LabelTemplateStorage: Successfully deleted template: $name'); // DEBUG
    } else {
      print('LabelTemplateStorage: Template not found for deletion: $name'); // DEBUG
    }
  }
}