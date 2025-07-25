import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Setting extends StatefulWidget {
  const Setting({Key? key}) : super(key: key);

  @override
  State<Setting> createState() => _SettingState();
}

class _SettingState extends State<Setting> {
  final _oldPinCtrl = TextEditingController();
  final _newPinCtrl = TextEditingController();
  final _confirmPinCtrl = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  String? _savedPin;

  @override
  void initState() {
    super.initState();
    _loadSavedPin();
  }

  Future<void> _loadSavedPin() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _savedPin = prefs.getString('user_pin');
    });
  }

  Future<void> _saveNewPin() async {
    final oldPin = _oldPinCtrl.text;
    final newPin = _newPinCtrl.text;
    final confirmPin = _confirmPinCtrl.text;

    if (oldPin != _savedPin) {
      _showMessage('Incorrect current PIN');
      return;
    }

    if (newPin != confirmPin) {
      _showMessage('PINs do not match');
      return;
    }

    if (newPin.length != 4) {
      _showMessage('PIN must be exactly 4 digits');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_pin', newPin);
    _showMessage('PIN changed successfully');
    _oldPinCtrl.clear();
    _newPinCtrl.clear();
    _confirmPinCtrl.clear();
    setState(() => _savedPin = newPin);
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Change App PIN',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 30),
              TextFormField(
                controller: _oldPinCtrl,
                obscureText: true,
                maxLength: 4,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: const InputDecoration(
                  labelText: 'Current PIN',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _newPinCtrl,
                obscureText: true,
                maxLength: 4,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: const InputDecoration(
                  labelText: 'New PIN',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmPinCtrl,
                obscureText: true,
                maxLength: 4,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: const InputDecoration(
                  labelText: 'Confirm New PIN',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('Save'),
                onPressed: _saveNewPin,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  iconColor: Color(0xFF0E1B4B),

                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
