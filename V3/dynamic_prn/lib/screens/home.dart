// screens/home.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/label_form_model.dart';
import '../models/label_template.dart';
import '../models/label_template_storage.dart';
import 'dynamic_form_setup_screen.dart';
import 'dynamic_form_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  LabelFormModel? _form;
  bool _loading = true;
  late AnimationController _controller;

  // Define theme colors for this screen
  final Color charcoalColor = const Color(0xFF33485D); // Dark Blue/Grey
  final Color whiteColor = Colors.white; // White
  final Color vibrantGreen = const Color(0xFF00C853); // A brighter green for accents

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _loadLastUsedTemplate(); // Load the last used template on app start
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadLastUsedTemplate() async {
    setState(() {
      _loading = true;
    });

    final prefs = await SharedPreferences.getInstance();
    final lastUsedName = prefs.getString('last_used_template_name');

    LabelFormModel? loadedForm;
    if (lastUsedName != null && lastUsedName.isNotEmpty) {
      loadedForm = await LabelFormModel.load(lastUsedName);
    }

    setState(() {
      _form = loadedForm;
      _loading = false;
    });
    print('HomePage: _loadLastUsedTemplate completed. Form loaded: ${_form?.name}'); // DEBUG
  }

  Future<void> _pickPrnAndGenerate() async {
    final perm = await Permission.manageExternalStorage.request();
    if (!perm.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Storage permission denied')),
      );
      return;
    }

    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
      if (res == null || res.files.single.bytes == null) return;

      final raw = String.fromCharCodes(res.files.single.bytes!);
      final qRE = RegExp(r'"([^"]+)"\s*$', multiLine: true);
      final quoted = qRE.allMatches(raw).map((m) => m.group(1)!).toList();

      if (quoted.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No quoted values found.')),
        );
        return;
      }

      final bRE = RegExp(r'(BARCODE|QRCODE)[^\n]*"([^"]+)"', multiLine: true);
      final barcodeVars = bRE.allMatches(raw).map((m) => m.group(2)!).toList();

      if (!mounted) return;
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DynamicFormSetupScreen(
            extracted: quoted,
            rawPrn: raw,
            barcodeVars: barcodeVars,
          ),
        ),
      );

      if (result == 'reload') {
        print('HomePage: Setup screen returned "reload". Reloading last used template.'); // DEBUG
        await _loadLastUsedTemplate(); // Reload after setup is complete
      }

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error reading PRN: $e')),
      );
    }
  }

  Future<void> _loadTemplate() async {
    final prefs = await SharedPreferences.getInstance();
    List<LabelTemplate> currentTemplates = await LabelTemplateStorage.loadTemplates();
    print('HomePage: Attempting to load template. Found ${currentTemplates.length} templates.'); // DEBUG

    if (currentTemplates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No named templates found.")),
      );
      return;
    }

    await showDialog<LabelTemplate>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: Text('Load or Delete Template', style: TextStyle(color: charcoalColor)),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: currentTemplates.length,
                  itemBuilder: (_, i) {
                    final t = currentTemplates[i];
                    return ListTile(
                      title: Text(t.name, style: TextStyle(color: charcoalColor)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: dialogContext,
                            builder: (ctx2) => AlertDialog(
                              title: Text('Delete Template?', style: TextStyle(color: charcoalColor)),
                              content: Text('Are you sure you want to delete "${t.name}"?', style: TextStyle(color: charcoalColor)),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx2, false),
                                  child: Text('Cancel', style: TextStyle(color: charcoalColor)),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx2, true),
                                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await LabelTemplateStorage.deleteTemplate(t.name);
                            // Only delete LabelFormModel if it exists and matches this template name
                            final currentForm = await LabelFormModel.load(t.name);
                            if (currentForm != null) {
                              await LabelFormModel.delete(t.name);
                              print('HomePage: Deleted corresponding LabelFormModel for ${t.name}'); // DEBUG
                            }


                            setDialogState(() {
                              currentTemplates.removeAt(i);
                            });

                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Template "${t.name}" deleted')),
                            );
                            // If the deleted template was the active one, clear current form and reload.
                            // Otherwise, just reload to update the list.
                            if (_form?.name == t.name) {
                              setState(() {
                                _form = null; // Clear the displayed form
                              });
                              await prefs.remove('last_used_template_name'); // Clear last used preference
                              print('HomePage: Deleted active template. _form set to null.'); // DEBUG
                            }
                            // No need to call _loadLastUsedTemplate here unless you want to
                            // immediately try to load *another* last used template.
                            // The user will see the "No label form loaded" message if _form is null.
                            // If they delete a non-active template, the screen won't change,
                            // only the list in the dialog will update.
                          }
                        },
                      ),
                      onTap: () async {
                        print('HomePage: User selected template: ${t.name}'); // DEBUG
                        Navigator.pop(dialogContext); // Close the template selection dialog

                        // IMPORTANT CHANGE: Load the full LabelFormModel directly by its name
                        final loadedForm = await LabelFormModel.load(t.name);

                        if (loadedForm != null) {
                          setState(() {
                            _form = loadedForm; // Update the main form in HomePage's state
                          });
                          await prefs.setString('last_used_template_name', t.name); // Set as last used
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Template "${t.name}" loaded')),
                            );
                            print('HomePage: Successfully loaded and set _form to ${loadedForm.name}'); // DEBUG
                          }
                        } else {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: Could not load full form data for "${t.name}"')),
                            );
                            print('HomePage: Failed to load LabelFormModel for ${t.name}'); // DEBUG
                          }
                        }
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text('Cancel', style: TextStyle(color: charcoalColor)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.grey[100],

        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _loading
                  ? Center(
                child: ScalePrinterLoader(controller: _controller),
              )
                  : _form != null
                  ? DynamicFormScreen.inline(
                key: ValueKey(_form!.toJson().toString()),
                form: _form!,
                onSaved: () async {
                  // When DynamicFormScreen saves its data (e.g., after print)
                  // It means the underlying LabelFormModel has been saved.
                  // We should then reload it into HomePage's state to ensure UI is updated
                  // and the latest version is reflected if the app restarts.
                  print('HomePage: DynamicFormScreen onSaved triggered. Reloading last used template.'); // DEBUG
                  await _loadLastUsedTemplate();
                },
              )
                  : Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.description, size: 80, color: charcoalColor.withOpacity(0.7)),
                      const SizedBox(height: 20),
                      Text(
                        'No label form loaded yet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: charcoalColor),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Tap the "+" button at the bottom right to upload a new PRN or load a saved template.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: charcoalColor),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            showModalBottomSheet(
              context: context,
              builder: (BuildContext context) {
                return Container(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      ListTile(
                        leading: Icon(Icons.upload_file, color: charcoalColor),
                        title: Text('Upload New PRN', style: TextStyle(color: charcoalColor, fontSize: 18)),
                        onTap: () {
                          Navigator.pop(context);
                          _pickPrnAndGenerate();
                        },
                      ),
                      ListTile(
                        leading: Icon(Icons.folder_open, color: charcoalColor),
                        title: Text('Load Template', style: TextStyle(color: charcoalColor, fontSize: 18)),
                        onTap: () {
                          Navigator.pop(context);
                          _loadTemplate();
                        },
                      ),
                    ],
                  ),
                );
              },
            );
          },
          child: Icon(Icons.add, color: whiteColor),
          backgroundColor: charcoalColor,
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      ),
    );
  }
}

class ScalePrinterLoader extends StatelessWidget {
  final AnimationController controller;
  const ScalePrinterLoader({super.key, required this.controller});

  final Color charcoalColor = const Color(0xFF33485D);
  final Color vibrantGreen = const Color(0xFF00C853);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        RotationTransition(
          turns: Tween(begin: 0.0, end: 1.0).animate(controller),
          child: Icon(Icons.scale, size: 80, color: vibrantGreen),
        ),
        const SizedBox(height: 20),
        ScaleTransition(
          scale: Tween(begin: 1.0, end: 1.2).animate(controller),
          child: Icon(Icons.print, size: 60, color: charcoalColor),
        ),
        const SizedBox(height: 20),
        Text(
          "Loading Scale & Printer...",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: charcoalColor),
        ),
      ],
    );
  }
}