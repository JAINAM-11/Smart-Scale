import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final currentPinController = TextEditingController();
  final newPinController = TextEditingController();
  final confirmPinController = TextEditingController();
  String _errorMessage = ''; // Changed variable name to avoid conflict with `error` getter

  // Define theme colors for this screen, consistent with DynamicFormScreen
  final Color charcoalColor = const Color(0xFF33485D); // Dark Blue/Grey
  final Color whiteColor = Colors.white; // White (mostly for text/icons on dark backgrounds)
  final Color vibrantGreen = const Color(0xFF00C853); // A brighter green for accents
  final Color lightTextColor = Colors.grey[600]!; // For hint text

  @override
  void dispose() {
    currentPinController.dispose();
    newPinController.dispose();
    confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _changePin() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPin = prefs.getString('user_pin') ?? '1234'; // Assuming 'user_pin' is the key

    setState(() {
      _errorMessage = ''; // Clear previous errors
    });

    if (currentPinController.text != savedPin) {
      setState(() => _errorMessage = 'Incorrect current PIN');
      return;
    }

    if (newPinController.text != confirmPinController.text) {
      setState(() => _errorMessage = 'New PINs do not match');
      return;
    }

    if (newPinController.text.length != 4 || int.tryParse(newPinController.text) == null) {
      setState(() => _errorMessage = 'PIN must be a 4-digit number');
      return;
    }

    // Using 'user_pin' as the key to save, consistent with loading
    await prefs.setString('user_pin', newPinController.text);
    setState(() {
      _errorMessage = 'PIN changed successfully!'; // Success message
      currentPinController.clear();
      newPinController.clear();
      confirmPinController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100], // Light background color for the page body
      body: SingleChildScrollView( // Use SingleChildScrollView for better responsiveness
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, // Stretch children horizontally
          children: [
            Text(
              'Change PIN',
              style: TextStyle(
                color: charcoalColor,
                fontWeight: FontWeight.bold,
                fontSize: 26,
                // fontFamily: 'Montserrat', // Uncomment if you have a custom font
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: currentPinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4, // Max length for PIN input
              decoration: InputDecoration(
                labelText: 'Current PIN',
                labelStyle: TextStyle(color: charcoalColor),
                hintText: 'Enter your current 4-digit PIN',
                hintStyle: TextStyle(color: lightTextColor),
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
                counterText: "", // Hide character counter
              ),
              style: TextStyle(color: charcoalColor),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: newPinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4, // Max length for PIN input
              decoration: InputDecoration(
                labelText: 'New PIN',
                labelStyle: TextStyle(color: charcoalColor),
                hintText: 'Enter new 4-digit PIN',
                hintStyle: TextStyle(color: lightTextColor),
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
                counterText: "", // Hide character counter
              ),
              style: TextStyle(color: charcoalColor),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: confirmPinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4, // Max length for PIN input
              decoration: InputDecoration(
                labelText: 'Confirm PIN',
                labelStyle: TextStyle(color: charcoalColor),
                hintText: 'Re-enter new PIN',
                hintStyle: TextStyle(color: lightTextColor),
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
                counterText: "", // Hide character counter
              ),
              style: TextStyle(color: charcoalColor),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _changePin,
              style: ElevatedButton.styleFrom(
                backgroundColor: charcoalColor, // Button background
                foregroundColor: whiteColor, // Text color
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10), // Rounded corners
                ),
                elevation: 5, // Add some shadow
              ),
              child: const Text(
                'Change PIN',
                style: TextStyle(fontSize: 18),
              ),
            ),
            if (_errorMessage.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage,
                style: TextStyle(
                  color: _errorMessage.contains('successfully') ? vibrantGreen : Colors.red,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}