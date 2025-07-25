import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:testscaling/navbar.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Re-enter PIN to confirm"),
          duration: Duration(seconds: 2),
        ));
        setState(() {});
      } else {
        if (enteredPin == tempPin) {
          _savePin(enteredPin);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("PIN set successfully!"),
            duration: Duration(seconds: 2),
          ));
          setState(() {
            savedPin = enteredPin;
            isSettingPin = false;
            isConfirming = false;
            tempPin = null;
            enteredPin = '';
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("PINs do not match. Try again."),
            duration: Duration(seconds: 2),
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
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const NavBar()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Incorrect PIN."),
          duration: Duration(seconds: 2),
        ));
        setState(() {
          enteredPin = '';
        });
      }
    }
  }

  Widget roundedButton({required Widget child, required VoidCallback onPressed}) {
    return SizedBox(
      width: 70,
      height: 70,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: TextButton(
          style: TextButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: onPressed,
          child: child,
        ),
      ),
    );
  }

  Widget numButton(int number) {
    return roundedButton(
      child: Text(
        number.toString(),
        style: const TextStyle(
          fontSize: 24,
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      onPressed: () {
        setState(() {
          if (enteredPin.length < 4) {
            enteredPin += number.toString();
            if (enteredPin.length == 4) {
              Future.delayed(const Duration(milliseconds: 100), _submitPin);
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
        backgroundColor: Colors.blue,
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 150, 20, 20),
          physics: const BouncingScrollPhysics(),
          children: [
            Center(
              child: Column(
                children: [
                  Text(
                    isSettingPin
                        ? isConfirming
                        ? 'Confirm PIN'
                        : 'Set PIN'
                        : 'Enter PIN',
                    style: const TextStyle(
                      fontSize: 32,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isSettingPin
                        ? isConfirming
                        ? 'Re-enter your PIN to confirm'
                        : 'Please set a 4-digit PIN'
                        : 'Please enter your PIN to continue',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 60, bottom: 60),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  return Container(
                    margin: const EdgeInsets.all(6),
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      color: Colors.blue[300]
                    ),
                    child: index < enteredPin.length
                        ? Center(
                      child: isPinVisible
                          ? Text(
                        enteredPin[index],
                        style: const TextStyle(
                          fontSize: 22,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                          : const Text(
                        '✶',
                        style: TextStyle(
                          fontSize: 20,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                        : null,
                  );
                }),
              ),
            ),

            // Buttons 1-9
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(3, (index) => numButton(1 + 3 * i + index)),
                ),
              ),

            // Last row (clear, 0, backspace)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  roundedButton(
                    child: const Icon(Icons.clear, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        enteredPin = '';
                      });
                    },
                  ),
                  numButton(0),
                  roundedButton(
                    child: const Icon(Icons.backspace, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        if (enteredPin.isNotEmpty) {
                          enteredPin = enteredPin.substring(0, enteredPin.length - 1);
                        }
                      });
                    },
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
