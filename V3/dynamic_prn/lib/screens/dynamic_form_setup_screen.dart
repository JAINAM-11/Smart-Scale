// screens/dynamic_form_setup_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/label_form_model.dart';
import '../models/label_template.dart';
import '../models/label_template_storage.dart';

class DynamicFormSetupScreen extends StatefulWidget {
  final List<String> extracted; // quoted strings
  final String rawPrn; // full PRN template
  final List<String> barcodeVars;

  final Future<void> Function()? onSaved;

  const DynamicFormSetupScreen({
    super.key,
    required this.extracted,
    required this.rawPrn,
    required this.barcodeVars,
    this.onSaved,
  });

  @override
  State<DynamicFormSetupScreen> createState() => _DynamicFormSetupScreenState();
}

class _DynamicFormSetupScreenState extends State<DynamicFormSetupScreen> {
  late List<String> pool; // remaining unmapped strings
  final Map<String, String> pairs = {}; // {title -> value}
  final List<String> barcodeFields = []; // titles selected for barcode
  String barcodeSep = ' '; // Default separator is space
  String? scaleInputTitle; // NEW: To store the selected scale input field

  String? selectedTitle;
  final _search = TextEditingController();

  // Define predefined separator options
  final List<String> _separatorOptions = [' ', '-', '_', '.', ',', '/'];
  // Display names for separators (optional, for better UI)
  final Map<String, String> _separatorDisplayNames = {
    ' ': 'Space ( )',
    '-': 'Hyphen (-)',
    '_': 'Underscore (_)',
    '.': 'Dot (.)',
    ',': 'Comma (,)',
    '/': 'Slash (/)',
  };

  // Define theme colors for this screen
  final Color charcoalColor = const Color(0xFF33485D); // Dark Blue/Grey
  final Color whiteColor = Colors.white; // White
  // Updated to the specified green color: 0xFF26BA9A
  final Color customGreen = const Color(0xFF26BA9A);
  final Color lightTextColor = Colors.grey[600]!; // For hint text

  @override
  void initState() {
    super.initState();
    pool = List<String>.from(
      widget.extracted.where((s) => !widget.barcodeVars.contains(s)),
    );
    _search.addListener(() => setState(() {})); // Rebuilds on search text change
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /* ──────────────────────────────────────────────────────────────── */
  void _tap(String item) {
    setState(() {
      if (selectedTitle == null) {
        selectedTitle = item; // choose title first
      } else {
        if (item != selectedTitle) {
          pairs[selectedTitle!] = item; // title mapped to value
          pool.remove(selectedTitle);
          pool.remove(item);
        }
        selectedTitle = null;
      }
    });
  }

  void _undo(String title) {
    setState(() {
      final val = pairs.remove(title);
      if (val != null) {
        pool.insert(0, title);
        pool.insert(1, val);
      }
      barcodeFields.remove(title);
      // NEW: If the undone field was the scale input, clear it
      if (scaleInputTitle == title) {
        scaleInputTitle = null;
      }
    });
  }

  /* ── Persist & return ──────────────────────────────────────────── */
  Future<void> _finish() async {
    if (pairs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Map at least one field')),
      );
      return;
    }

    final orig = <String, String>{};
    for (var e in pairs.entries) {
      orig[e.key] = e.value;
    }

    String? templateName;
    await showDialog(
      context: context,
      builder: (context) {
        final nameController = TextEditingController();
        return AlertDialog(
          title: Text('Template Name', style: TextStyle(color: charcoalColor)),
          content: TextField(
            controller: nameController,
            decoration: InputDecoration(
              hintText: 'Enter template name',
              hintStyle: TextStyle(color: lightTextColor),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: charcoalColor.withOpacity(0.5)),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: customGreen, width: 2),
              ),
            ),
            style: TextStyle(color: charcoalColor),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text('Cancel', style: TextStyle(color: charcoalColor)),
            ),
            ElevatedButton(
              onPressed: () {
                templateName = nameController.text.trim().isEmpty
                    ? 'Unnamed'
                    : nameController.text.trim();
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: charcoalColor,
                foregroundColor: whiteColor,
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (templateName == null) return;

    final model = LabelFormModel(
      rawPrn: widget.rawPrn,
      titleData: pairs,
      originalPrnValues: orig,
      barcodeTitles: barcodeFields,
      barcodeSeparator: barcodeSep,
      name: templateName!,
      scaleInputTitle: scaleInputTitle, // NEW: Pass the selected scale input title
    );

    await LabelFormModel.save(model);

    final template = LabelTemplate(
      name: templateName!,
      fields: pairs,
      barcodeFields: barcodeFields,
      separator: barcodeSep,
    );
    await LabelTemplateStorage.saveTemplate(template);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_used_template_name', templateName!);

    if (!mounted) return;
    Navigator.pop(context, 'reload');
  }

  /* ──────────────────────────────────────────────────────────────── */
  @override
  Widget build(BuildContext ctx) {
    final list = _search.text.isEmpty
        ? pool
        : pool
        .where((s) => s.toLowerCase().contains(_search.text.toLowerCase()))
        .toList();

    final bool isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(
          'Tap to Match Fields',
          style: TextStyle(
              color: whiteColor, fontWeight: FontWeight.bold, fontSize: 22),
        ),
        backgroundColor: charcoalColor,
        iconTheme: IconThemeData(color: whiteColor),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search strings…',
                hintStyle: TextStyle(color: lightTextColor),
                prefixIcon: Icon(Icons.search, color: charcoalColor),
                suffixIcon: _search.text.isNotEmpty
                    ? IconButton(
                  icon: Icon(Icons.clear, color: charcoalColor),
                  onPressed: _search.clear,
                )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: charcoalColor.withOpacity(0.5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: customGreen, width: 2),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: charcoalColor.withOpacity(0.5)),
                ),
                filled: true,
                fillColor: whiteColor,
              ),
              style: TextStyle(color: charcoalColor),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final s = list[i];
                final sel = s == selectedTitle;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  color: sel ? customGreen.withOpacity(0.3) : whiteColor,
                  child: ListTile(
                    title: Text(
                      s,
                      style: TextStyle(
                        color: sel ? charcoalColor : charcoalColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onTap: () => _tap(s),
                  ),
                );
              },
            ),
          ),

          if (!isKeyboardVisible) ...[
            Divider(color: charcoalColor.withOpacity(0.4), height: 24, thickness: 1),

            if (pairs.isNotEmpty) ...[
              SizedBox(
                height: 175,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Text('Mapped pairs (long-press to undo):',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: charcoalColor,
                              fontSize: 16)),
                    ),
                    Expanded(
                      child: Scrollbar(
                        thumbVisibility: true,
                        child: ListView(
                          shrinkWrap: true,
                          physics: const ClampingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          children: pairs.entries
                              .map((e) => ListTile(
                            title: Text(
                              '${e.key}  →  ${e.value}',
                              style: TextStyle(color: charcoalColor),
                            ),
                            onLongPress: () => _undo(e.key),
                            contentPadding:
                            const EdgeInsets.symmetric(horizontal: 4),
                          ))
                              .toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            Divider(color: charcoalColor.withOpacity(0.4), height: 24, thickness: 1),

            // NEW: Scale Input Field Selection
            if (pairs.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text('Select field for Scale Input (optional):',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: charcoalColor,
                        fontSize: 16)),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(
                    bottom: 12, left: 16, right: 16),
                child: Row(
                  children: pairs.keys.map((t) {
                    final isSelected = scaleInputTitle == t;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(t,
                            style: TextStyle(
                                color: isSelected ? whiteColor : charcoalColor)),
                        selected: isSelected,
                        onSelected: (sel) => setState(() {
                          scaleInputTitle = sel ? t : null; // Toggle selection
                        }),
                        backgroundColor: whiteColor,
                        selectedColor: customGreen,
                        checkmarkColor: whiteColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                              color: isSelected
                                  ? customGreen
                                  : charcoalColor.withOpacity(0.5)),
                        ),
                        elevation: 2,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],

            /* barcode selection and separator */
            if (pairs.isNotEmpty) ...[
              Divider(color: charcoalColor.withOpacity(0.4), height: 24, thickness: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text('Select fields for BARCODE/QRCODE:',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: charcoalColor,
                        fontSize: 16)),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(
                    bottom: 12, left: 16, right: 16),
                child: Row(
                  children: pairs.keys.map((t) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(t,
                            style: TextStyle(
                                color: barcodeFields.contains(t)
                                    ? whiteColor
                                    : charcoalColor)),
                        selected: barcodeFields.contains(t),
                        onSelected: (sel) => setState(() {
                          sel ? barcodeFields.add(t) : barcodeFields.remove(t);
                        }),
                        backgroundColor: whiteColor,
                        selectedColor: customGreen,
                        checkmarkColor: whiteColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                              color: barcodeFields.contains(t)
                                  ? customGreen
                                  : charcoalColor.withOpacity(0.5)),
                        ),
                        elevation: 2,
                      ),
                    );
                  }).toList(),
                ),
              ),
              if (barcodeFields.length > 1)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text('Choose Barcode Separator (Default: Space):',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: charcoalColor,
                              fontSize: 16)),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                      child: Row(
                        children: _separatorOptions.map((sep) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(_separatorDisplayNames[sep] ?? sep,
                                  style: TextStyle(
                                      color: barcodeSep == sep ? whiteColor : charcoalColor)),
                              selected: barcodeSep == sep,
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() {
                                    barcodeSep = sep;
                                  });
                                }
                              },
                              checkmarkColor: whiteColor,
                              backgroundColor: whiteColor,
                              selectedColor: customGreen,
                              labelStyle: TextStyle(
                                  color: barcodeSep == sep ? whiteColor : charcoalColor),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(
                                    color: barcodeSep == sep
                                        ? customGreen
                                        : charcoalColor.withOpacity(0.5)),
                              ),
                              elevation: 2,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
            ],
          ],
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton.icon(
          onPressed: _finish,
          icon: Icon(Icons.check, color: whiteColor),
          label: Text(
            'Save & Generate Form',
            style: TextStyle(color: whiteColor, fontSize: 18),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: charcoalColor,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            elevation: 5,
          ),
        ),
      ),
    );
  }
}