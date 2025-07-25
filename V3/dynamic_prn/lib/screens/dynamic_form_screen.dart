// screens/dynamic_form_screen.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../controllers/bluetooth_controller.dart';
import '../helper/loader_helper.dart';
import '../models/label_form_model.dart';
import '../models/label_template.dart';
import '../models/label_template_storage.dart';

class _Caps extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

class DynamicFormScreen extends StatefulWidget {
  final LabelFormModel form;
  final VoidCallback? onSaved;
  final bool embedded; // Flag to indicate if it's embedded in another screen

  const DynamicFormScreen({
    super.key,
    required this.form,
    this.onSaved,
    this.embedded = false, // Default to not embedded (i.e., full screen)
  });

  factory DynamicFormScreen.inline({
    Key? key,
    required LabelFormModel form,
    VoidCallback? onSaved,
  }) => DynamicFormScreen(key: key, form: form, embedded: true, onSaved: onSaved);

  @override
  State<DynamicFormScreen> createState() => _DynState();
}

class _DynState extends State<DynamicFormScreen> {
  late final Map<String, TextEditingController> _ctrl;
  late final Map<String, String> _units;
  late final String _netKey;
  late final String _tareBoxKey;
  late final String _tareBobbinKey;

  // Define theme colors for this screen
  final Color charcoalColor = const Color(0xFF33485D); // Dark Blue/Grey
  final Color whiteColor = Colors.white; // White (mostly for text/icons on dark backgrounds)
  final Color vibrantGreen = const Color(0xFF00C853); // A brighter green for accents
  final Color lightTextColor = Colors.grey[600]!; // For hint text

  @override
  void initState() {
    super.initState();
    _units = {};
    _ctrl = {};

    // --- ADDED DEBUGGING ---
    print('DynamicFormScreen initState: Form Name: ${widget.form.name}');
    print('DynamicFormScreen initState: Scale Input Title (from form): "${widget.form.scaleInputTitle}"');
    // --- END DEBUGGING ---

    for (final entry in widget.form.titleData.entries) {
      final title = entry.key;
      final value = entry.value;

      if (_isWeight(title)) {
        final unitMatch = RegExp(r'(\d+(\.\d+)?)\s*([a-zA-Z]+)\s*(\$)?').firstMatch(value.trim());
        if (unitMatch != null && unitMatch.group(3) != null) {
          _units[title] = unitMatch.group(3)!;
        } else {
          _units[title] = 'kg';
        }
      }
      _ctrl[title] = TextEditingController();
      _ctrl[title]!.addListener(() => setState(() {}));

      String initialText = value;
      if (_isWeight(title)) {
        final match = RegExp(r'(\d+(\.\d+)?)\s*([a-zA-Z]+)\s*(\$)?').firstMatch(value.trim());
        if (match != null && match.group(1) != null) {
          initialText = match.group(1)!;
        } else {
          initialText = value.replaceAll(RegExp(r'[^0-9.]'), '');
        }
      }
      _ctrl[title]!.text = initialText;
    }

    _netKey = _findKeyContaining('net');
    _tareBoxKey = _findKeyContaining('box');
    _tareBobbinKey = _ctrl.keys.firstWhere(
          (k) => k.toLowerCase().contains('bobbin') && k.toLowerCase().contains('weight'),
      orElse: () => '',
    );

    if (_tareBoxKey.isNotEmpty) _ctrl[_tareBoxKey]!.addListener(_calcNet);
    if (_tareBobbinKey.isNotEmpty) _ctrl[_tareBobbinKey]!.addListener(_calcNet);
  }

  @override
  void dispose() {
    for (var controller in _ctrl.values) {
      controller.removeListener(() => setState(() {}));
      controller.dispose();
    }
    super.dispose();
  }

  String _findKeyContaining(String word) =>
      _ctrl.keys.firstWhere((k) => k.toLowerCase().contains(word), orElse: () => '');

  bool _isWeight(String title) {
    final l = title.toLowerCase();
    return l.contains('weight') || l.contains('gross') || l.contains('tare') || l.contains('net');
  }

  double _toNum(String s) =>
      double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;

  int _decimals(String s) {
    final m = RegExp(r'\.(\d+)').firstMatch(s);
    return m?.group(1)?.length ?? 0;
  }

  String _unitOf(String key) => _units[key] ?? 'kg'; // Simplified unit lookup

  void _calcNet() {
    // Use the explicitly defined scaleInputTitle as the "gross" source for calculations
    final String grossSourceKey = widget.form.scaleInputTitle ?? _findKeyContaining('gross');

    if (_netKey.isEmpty || grossSourceKey.isEmpty) return;

    final grossStr = _ctrl[grossSourceKey]?.text ?? '';
    final gross = _toNum(grossStr);
    final tareBox = _toNum(_ctrl[_tareBoxKey]?.text ?? '');
    final tareBobbin = _toNum(_ctrl[_tareBobbinKey]?.text ?? '');

    final net = gross - tareBox - tareBobbin;
    final formatted = net.toStringAsFixed(_decimals(grossStr));

    _ctrl[_netKey]?.text = formatted;
    // Ensure the unit for net is consistent with gross or default
    _units[_netKey] = _unitOf(grossSourceKey);
  }


  Future<void> _fetchGross() async {
    // Use the explicitly defined scaleInputTitle
    final String targetKey = widget.form.scaleInputTitle ?? _findKeyContaining('gross');
    if (targetKey.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No field designated for scale input.')),
        );
      }
      return;
    }

    try {
      final line = await bluetoothController.readScaleLine();
      final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(line ?? '');
      if (m == null) throw 'Invalid scale data';

      final raw = m.group(1)!;
      final decimals = raw.contains('.') ? raw.split('.')[1].length : 0;
      final formatted = double.parse(raw).toStringAsFixed(decimals);

      _ctrl[targetKey]?.text = formatted;
      _calcNet();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scale read failed: $e')));
    }
  }

  Future<void> _print({int copies = 1}) async {
    var tspl = widget.form.rawPrn;

    for (final title in widget.form.titleData.keys) {
      final original = widget.form.originalPrnValues[title] ?? '';
      var edited = _ctrl[title]!.text.trim();

      if (_isWeight(title)) {
        final unit = _unitOf(title);
        final originalHasUnitPattern = RegExp(r'\d+\s*[a-zA-Z]+\s*\$').hasMatch(original);
        final originalHasUnitPatternNoDollar = RegExp(r'\d+\s*[a-zA-Z]+$').hasMatch(original);

        if (originalHasUnitPattern || originalHasUnitPatternNoDollar) {
          edited = '$edited$unit';
        }
      }

      if (original.isNotEmpty) {
        tspl = tspl.replaceAll(RegExp('"${RegExp.escape(original)}"'), '"$edited"');
      }
    }

    tspl = _patchBarcode(tspl);
    tspl = tspl.replaceAll(
      RegExp(r'PRINT\s*\d*(,\s*\d*)?', caseSensitive: false),
      'PRINT $copies,1',
    );

    print('--- Raw TSPL being sent to printer ---\n$tspl\n--------------------------------------');

    // Save the updated form data before printing
    final updated = widget.form.copyWith(
      titleData: {
        for (final e in _ctrl.entries)
          e.key: _isWeight(e.key) ? '${e.value.text}${_unitOf(e.key)}' : e.value.text
      },
      name: widget.form.name,
      rawPrn: widget.form.rawPrn,
      originalPrnValues: widget.form.originalPrnValues,
      barcodeTitles: widget.form.barcodeTitles,
      barcodeSeparator: widget.form.barcodeSeparator,
      scaleInputTitle: widget.form.scaleInputTitle, // Preserve this field
    );
    await LabelFormModel.save(updated);
    widget.onSaved?.call();

    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: LoaderHelper.printerLoader(width: 120, height: 120),
      ),
    );

    await Future.delayed(const Duration(milliseconds: 100));

    try {
      await bluetoothController.printRawTspl(tspl);
      print('✅ Print completed');
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sent to printer')),
        );
        if (!widget.embedded) {
          Navigator.of(context).pop();
        }
      }
    } catch (e, stack) {
      print('❌ Print failed: $e');
      print('🧱 Stack trace: $stack');

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print failed: $e')),
        );
      }
    }
  }

  String _patchBarcode(String prn) {
    final parts = widget.form.barcodeTitles.map((t) => _ctrl[t]?.text ?? '').toList();
    var payload = parts.join(widget.form.barcodeSeparator);
    if (parts.length == 1 && RegExp(r'^\d+\.\d+\$').hasMatch(payload)) {
      payload = payload.replaceAll('.', ' ');
    }

    final lines = prn.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].contains(RegExp(r'\b(BARCODE|QRCODE)\b'))) {
        final lastQ = lines[i].lastIndexOf('"');
        final prevQ = lines[i].lastIndexOf('"', lastQ - 1);
        if (prevQ != -1) {
          lines[i] = '${lines[i].substring(0, prevQ + 1)}$payload${lines[i].substring(lastQ)}';
        }
      }
    }
    return lines.join('\n');
  }

  Future<void> _askCopiesAndPrint() async {
    final ctrl = TextEditingController(text: '1');

    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Number of Copies'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Enter number of copies',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = int.tryParse(ctrl.text.trim());
              if (val != null && val > 0) {
                Navigator.pop(context, val);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a valid number of copies (e.g., 1)')),
                );
              }
            },
            child: const Text('Print'),
          ),
        ],
      ),
    );

    if (result != null) {
      _print(copies: result);
    }
  }

  Future<void> _saveTemplate() async {
    final nameController = TextEditingController(text: widget.form.name);

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Save Template', style: TextStyle(color: charcoalColor)),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: 'Template Name',
            hintText: 'Enter name to save/update template',
            labelStyle: TextStyle(color: charcoalColor),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: charcoalColor.withOpacity(0.5)),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: charcoalColor, width: 2),
            ),
          ),
          style: TextStyle(color: charcoalColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: charcoalColor)),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Template name cannot be empty')),
                );
                return;
              }

              // 1. Create an updated LabelFormModel with current field values
              final updatedFormModel = widget.form.copyWith(
                name: name, // Allow changing the name if desired
                titleData: {
                  for (final e in _ctrl.entries)
                    e.key: _isWeight(e.key) ? '${e.value.text}${_unitOf(e.key)}' : e.value.text
                },
                // Keep rawPrn, originalPrnValues, barcodeTitles, barcodeSeparator, and scaleInputTitle as they are
                // since they are not directly edited in this screen's fields but are part of the model.
                rawPrn: widget.form.rawPrn,
                originalPrnValues: widget.form.originalPrnValues,
                barcodeTitles: widget.form.barcodeTitles,
                barcodeSeparator: widget.form.barcodeSeparator,
                scaleInputTitle: widget.form.scaleInputTitle,
              );

              // 2. Save the full LabelFormModel to its dedicated storage
              await LabelFormModel.save(updatedFormModel);

              // 3. Create and save the LabelTemplate (which only holds field values)
              final template = LabelTemplate(
                name: name,
                fields: {
                  for (final e in _ctrl.entries) e.key: e.value.text,
                },
                barcodeFields: widget.form.barcodeTitles,
                separator: widget.form.barcodeSeparator,
              );

              await LabelTemplateStorage.saveTemplate(template);

              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Template "$name" saved')),
                );
                // Inform the parent (HomePage) that the form has been saved, so it can reload
                widget.onSaved?.call();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: charcoalColor,
              foregroundColor: whiteColor,
            ),
            child: const Text('Save'),
          )
        ],
      ),
    );
  }

  Future<void> _loadTemplate() async {
    final templates = await LabelTemplateStorage.loadTemplates();

    if (templates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No saved templates found')),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (_) => SimpleDialog(
        title: Text('Select a Template', style: TextStyle(color: charcoalColor)),
        children: templates
            .map((t) => SimpleDialogOption(
          onPressed: () {
            Navigator.pop(context);
            // This _applyTemplate method in DynamicFormScreen ONLY applies the field values.
            // The full LabelFormModel loading (which includes rawPrn and scaleInputTitle)
            // now happens in HomePage when a template is selected from the bottom sheet.
            // So, calling _applyTemplate here is somewhat redundant if HomePage is reloading,
            // but it's harmless for immediate UI update.
            _applyTemplate(t);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(t.name, style: TextStyle(color: charcoalColor, fontSize: 16)),
          ),
        ))
            .toList(),
      ),
    );
  }

  void _applyTemplate(LabelTemplate template) {
    setState(() {
      for (final entry in template.fields.entries) {
        if (_ctrl.containsKey(entry.key)) {
          _ctrl[entry.key]?.text = entry.value;
        }
      }
      _calcNet();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Template "${template.name}" loaded')),
    );
  }

  Widget _fieldRow(String title, TextEditingController ctrl) {
    final lower = title.toLowerCase();
    final bool isScaleInput = widget.form.scaleInputTitle == title;

    // --- ADDED DEBUGGING ---
    print('  _fieldRow: Field Title: "$title", Is Scale Input Field: $isScaleInput');
    // --- END DEBUGGING ---

    final bool isNet = lower.contains('net') && _netKey.isNotEmpty;
    final bool isDate = lower.contains('date');
    final bool isWeight = _isWeight(title);

    final originalVal = widget.form.titleData[title] ?? '';
    final isNumericMisc = RegExp(r'^\d+(\.\d+)?$').hasMatch(originalVal.trim());

    Widget? suffixIcon;
    if (isScaleInput) {
      suffixIcon = IconButton(
        icon: Icon(Icons.monitor_weight, color: charcoalColor),
        onPressed: _fetchGross, // This is the callback we want to be clickable
        tooltip: 'Fetch weight from scale',
      );
    } else if (isDate) {
      suffixIcon = IconButton(
        icon: Icon(Icons.calendar_today, color: charcoalColor),
        onPressed: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime.now(),
            builder: (context, child) {
              return Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: ColorScheme.light(
                    primary: charcoalColor,
                    onPrimary: whiteColor,
                    onSurface: charcoalColor,
                  ),
                  textButtonTheme: TextButtonThemeData(
                    style: TextButton.styleFrom(
                      foregroundColor: charcoalColor,
                    ),
                  ),
                ),
                child: child!,
              );
            },
          );
          if (picked != null) {
            ctrl.text =
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
          }
        },
        tooltip: 'Select date',
      );
    } else if (ctrl.text.isNotEmpty) {
      suffixIcon = IconButton(
        icon: Icon(Icons.clear, color: charcoalColor),
        onPressed: () {
          ctrl.clear();
          if (lower.contains('tare')) {
            _calcNet();
          }
        },
        tooltip: 'Clear text',
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        readOnly: isNet || isDate || isScaleInput, // Prevent manual typing for these
        // FIX: Change 'enabled' logic. We want the TextField to be enabled
        // so its suffix icon is clickable, even if it's readOnly.
        enabled: !isNet, // Only disable if it's a net (calculated) field
        keyboardType: isWeight || isNumericMisc
            ? const TextInputType.numberWithOptions(decimal: true)
            : (isDate ? TextInputType.none : TextInputType.text),
        inputFormatters: isDate ? [] : [_Caps()],
        decoration: InputDecoration(
          labelText: title,
          suffixText: isWeight ? _unitOf(title) : null,
          suffixIcon: suffixIcon,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: charcoalColor.withOpacity(0.5)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: charcoalColor, width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: charcoalColor.withOpacity(0.5)),
          ),
          filled: true,
          fillColor: whiteColor,
          labelStyle: TextStyle(color: charcoalColor),
          hintStyle: TextStyle(color: lightTextColor),
        ),
        style: TextStyle(color: charcoalColor),
        // onTap is still handled by the suffixIcon for date/scaleInput
        onTap: isDate || isScaleInput
            ? () {
          // If it's a date or scale input field, tapping the text field
          // itself does nothing as the action is tied to the suffixIcon.
          // This prevents the keyboard from popping up for scale input.
        }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titles = _ctrl.keys.toList();

    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: widget.embedded
            ? null
            : AppBar(
          title: Text(
            'Label Fields',
            style: TextStyle(
                color: whiteColor, fontWeight: FontWeight.bold, fontSize: 22),
          ),
          backgroundColor: charcoalColor,
          iconTheme: IconThemeData(color: whiteColor),
          actions: [
            IconButton(
              icon: Icon(Icons.folder_open, color: whiteColor, size: 28),
              tooltip: 'Load Template',
              onPressed: _loadTemplate,
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Label Fields',
                      style: TextStyle(
                        color: charcoalColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 26,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.save, color: charcoalColor, size: 28),
                      tooltip: 'Save Template',
                      onPressed: _saveTemplate,
                    ),
                  ],
                ),
              ),
              if (titles.isNotEmpty && !widget.embedded) const SizedBox(height: 20),
              for (final t in titles) _fieldRow(t, _ctrl[t]!),
              const SizedBox(height: 24),
              Center(
                child: ElevatedButton.icon(
                  onPressed: _askCopiesAndPrint,
                  icon: Icon(Icons.print, color: whiteColor),
                  label: Text(
                    'Print Label',
                    style: TextStyle(color: whiteColor, fontSize: 18),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: charcoalColor,
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}