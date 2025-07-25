// screens/login.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../navbar.dart'; // Make sure this path is correct

class PinCodeWidget extends StatefulWidget {
  const PinCodeWidget({super.key});

  @override
  State<PinCodeWidget> createState() => _PinCodeWidgetState();
}

class _PinCodeWidgetState extends State<PinCodeWidget> {
  String enteredPin = '';
  String? savedPin;
  String? tempPin;
  bool isPinVisible = false;
  bool isSettingPin = true;
  bool isConfirming = false;

  // Define your theme colors
  final Color backgroundColor = Colors.white; // Main background
  final Color charcoalColor = const Color(0xFF33485D); // Charcoal for PIN boxes and darker elements
  final Color mintColor = const Color(0xFF26BA9A); // Mint for number buttons and accents
  final Color textColorOnWhite = Colors.black; // Default text color on white background
  final Color textColorOnDark = Colors.white; // Text color on charcoal/mint elements
  final Color lightTextColor = Colors.grey[600]!; // Lighter text for subtitles

  @override
  void initState() {
    super.initState();
    _loadSavedPin();
  }

  Future<void> _loadSavedPin() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? pin = prefs.getString('user_pin');
    setState(() {
      savedPin = pin;
      isSettingPin = pin == null;
    });
  }

  Future<void> _savePin(String pin) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_pin', pin);
  }

  void _submitPin() {
    if (enteredPin.length != 4) return;

    if (isSettingPin) {
      if (!isConfirming) {
        tempPin = enteredPin;
        enteredPin = '';
        isConfirming = true;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Re-enter PIN to confirm", style: TextStyle(color: textColorOnDark)),
          backgroundColor: charcoalColor,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating, // Floating snackbar
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.all(16),
        ));
        setState(() {});
      } else {
        if (enteredPin == tempPin) {
          _savePin(enteredPin);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("PIN set successfully!", style: TextStyle(color: textColorOnDark)),
            backgroundColor: mintColor,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            margin: const EdgeInsets.all(16),
          ));
          setState(() {
            savedPin = enteredPin;
            isSettingPin = false;
            isConfirming = false;
            tempPin = null;
            enteredPin = '';
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("PINs do not match. Try again.", style: TextStyle(color: textColorOnDark)),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            margin: const EdgeInsets.all(16),
          ));
          setState(() {
            enteredPin = '';
            tempPin = null;
            isConfirming = false;
          });
        }
      }
    } else {
      if (enteredPin == savedPin) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Login successful!", style: TextStyle(color: textColorOnDark)),
          backgroundColor: mintColor,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.all(16),
        ));
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const NavBar()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Incorrect PIN.", style: TextStyle(color: textColorOnDark)),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.all(16),
        ));
        setState(() {
          enteredPin = '';
        });
      }
    }
  }

  // Refactored common button style
  Widget _buildKeypadButton({
    required Widget child,
    required VoidCallback onPressed,
    Color? buttonColor,
    Color? splashColor,
    Color? textColor,
    BoxBorder? border, // **CHANGED from BorderSide? to BoxBorder?**
  }) {
    return SizedBox(
      width: 75, // Slightly larger square buttons
      height: 75,
      child: Material(
        color: buttonColor ?? mintColor, // Default to mint for numbers
        borderRadius: BorderRadius.circular(12), // Rounded corners for squares
        clipBehavior: Clip.antiAlias,
        elevation: 3, // Add subtle elevation
        shadowColor: charcoalColor.withOpacity(0.3), // Soft shadow
        child: InkWell(
          onTap: onPressed,
          splashColor: splashColor ?? charcoalColor.withOpacity(0.2), // Charcoal splash
          highlightColor: charcoalColor.withOpacity(0.08), // Subtle highlight
          child: Container( // Wrap with Container to add border
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: border, // Apply the border here
            ),
            child: Center(
              child: DefaultTextStyle(
                style: TextStyle(color: textColor ?? this.textColorOnDark),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget numButton(int number) {
    return _buildKeypadButton(
      child: Text(
        number.toString(),
        style: const TextStyle(
          fontSize: 30, // Larger font for numbers
          fontWeight: FontWeight.w600,
        ),
      ),
      buttonColor: mintColor,
      textColor: textColorOnDark, // White text on mint buttons
      border: Border.all(color: charcoalColor.withOpacity(0.2), width: 2.0), // **Charcoal border for number buttons**
      onPressed: () {
        setState(() {
          if (enteredPin.length < 4) {
            enteredPin += number.toString();
            if (enteredPin.length == 4) {
              Future.delayed(const Duration(milliseconds: 200), _submitPin); // Slightly longer delay
            }
          }
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: backgroundColor, // Set main background to white
        body: ListView(
          padding: const EdgeInsets.fromLTRB(24, 80, 24, 24), // Adjusted padding
          physics: const BouncingScrollPhysics(),
          children: [
            Center(
              child: Column(
                children: [
                  Text(
                    isSettingPin
                        ? isConfirming
                        ? 'Confirm Your PIN'
                        : 'Set Your PIN'
                        : 'Enter Your PIN',
                    style: TextStyle(
                      fontSize: 34, // Larger title font
                      color: charcoalColor, // Charcoal color for title
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isSettingPin
                        ? isConfirming
                        ? 'Re-enter your 4-digit PIN to confirm.'
                        : 'Please set a 4-digit PIN for your account.'
                        : 'Please enter your 4-digit PIN to continue.',
                    style: TextStyle(
                      fontSize: 17, // Slightly larger subtitle
                      color: lightTextColor, // Lighter charcoal for subtitle
                      height: 1.4, // Improved line height
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 70, bottom: 60), // Increased vertical padding
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  bool filled = index < enteredPin.length;
                  bool isActiveInput = index == enteredPin.length; // Highlight the next box to fill

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    margin: const EdgeInsets.symmetric(horizontal: 8), // More spacing
                    width: 58, // Larger square boxes
                    height: 58,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10), // Rounded corners for squares
                      color: filled ? charcoalColor : Colors.white, // Filled charcoal, empty white
                      border: Border.all(
                        color: isActiveInput ? mintColor : charcoalColor.withOpacity(0.4), // Mint border for active, charcoal for others
                        width: isActiveInput ? 3 : 1.5, // Thicker border for active
                      ),
                      boxShadow: isActiveInput
                          ? [
                        BoxShadow(
                          color: mintColor.withOpacity(0.3),
                          blurRadius: 10,
                          spreadRadius: 2,
                          offset: const Offset(0, 4), // Slight shadow offset
                        ),
                      ]
                          : [],
                    ),
                    child: Center(
                      child: filled
                          ? (isPinVisible
                          ? Text(
                        enteredPin[index],
                        style: TextStyle(
                          fontSize: 26, // Larger number inside box
                          color: textColorOnDark, // White text on charcoal
                          fontWeight: FontWeight.bold,
                        ),
                      )
                          : Icon(
                        Icons.circle, // Solid circle for hidden PIN
                        size: 18,
                        color: textColorOnDark, // White circle on charcoal
                      ))
                          : null,
                    ),
                  );
                }),
              ),
            ),

            // Keypad grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10), // Adjusted horizontal padding
              child: Column(
                children: [
                  // Buttons 1-9
                  for (var i = 0; i < 3; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8), // Vertical spacing between rows
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround, // Distribute evenly
                        children: List.generate(3, (index) => numButton(1 + 3 * i + index)),
                      ),
                    ),

                  // Last row (clear/reset, 0, backspace)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        // Clear/Reset button
                        _buildKeypadButton(
                          child: Icon(Icons.refresh, color: charcoalColor, size: 30), // Charcoal icon
                          onPressed: () {
                            setState(() {
                              enteredPin = '';
                              tempPin = null; // Clear temp pin if user clears while confirming
                              isConfirming = false;
                            });
                          },
                          buttonColor: backgroundColor, // White background for control button
                          textColor: charcoalColor,
                          border: Border.all(color: charcoalColor.withOpacity(0.2), width: 2.0), // **Charcoal border for this button**
                        ),
                        numButton(0),
                        // Backspace button
                        _buildKeypadButton(
                          child: Icon(Icons.backspace_outlined, color: charcoalColor, size: 30), // Charcoal icon
                          onPressed: () {
                            setState(() {
                              if (enteredPin.isNotEmpty) {
                                enteredPin = enteredPin.substring(0, enteredPin.length - 1);
                              }
                            });
                          },
                          buttonColor: backgroundColor, // White background for control button
                          textColor: charcoalColor,
                          border: Border.all(color: charcoalColor.withOpacity(0.2), width: 2.0), // **Charcoal border for this button**
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}