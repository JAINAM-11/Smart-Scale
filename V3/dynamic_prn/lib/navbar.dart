// lib/navbar.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart'
as fb;
import 'package:permission_handler/permission_handler.dart';

import 'package:dynamic_prn/controllers/bluetooth_controller.dart';
import 'screens/home.dart'; // <-- make sure this path is correct
import 'screens/settings.dart'; // <-- make sure this path is correct

class NavBar extends StatefulWidget {
  const NavBar({super.key});

  @override
  State<NavBar> createState() => _NavBarState();
}

class _NavBarState extends State<NavBar> {
  int _tab = 0;
  Timer? _reconnectTimer;

  // Define your theme colors
  final Color charcoalColor = const Color(0xFF33485D); // Dark Blue/Grey
  final Color vibrantGreen = const Color(0xFF00C853); // A brighter green
  final Color whiteColor = Colors.white; // White
  final Color disconnectedColor = Colors.red; // Red for disconnected
  final Color lightTextColor = Colors.grey[600]!; // Lighter text for subtitles

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final granted = await _requestBluetoothPermissions();
      if (!granted) {
        if (mounted) {
          _showSnackBar(
            'Bluetooth permissions are required to connect to devices.',
            backgroundColor: disconnectedColor,
          );
        }
        return;
      }

      // Add a loading indicator while auto-reconnecting initially
      _showSnackBar(
        'Attempting to auto-connect devices...',
        backgroundColor: charcoalColor, // Using charcoal
        duration: const Duration(seconds: 3),
      );

      try {
        await bluetoothController.autoReconnectDevicesSequentially(
          onDeviceNotFoundDialog: (bool forScale) async {
            if (forScale) {
              await _showScaleDialog();
            } else {
              await _showPrinterDialog();
            }
          },
          context: context,
        ).timeout(const Duration(seconds: 8)); // Increased timeout for initial connect
      } on TimeoutException {
        // Handle initial timeout more gracefully if needed
        _showSnackBar(
          'Auto-connection timed out. Please connect manually.',
          backgroundColor: disconnectedColor,
        );
      } catch (e) {
        // General error during auto-reconnect
        _showSnackBar(
          'Auto-connection failed: ${e.toString()}',
          backgroundColor: disconnectedColor,
        );
      }
    });
    _startPeriodicReconnect();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    super.dispose();
  }

  void _startPeriodicReconnect() {
    _reconnectTimer?.cancel();

    _reconnectTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final timeout = const Duration(seconds: 10);

      // Only attempt to reconnect if not already connected
      if (!bluetoothController.scaleConnected || !bluetoothController.printerConnected) {
        try {
          await bluetoothController.autoReconnectDevicesSequentially(
            onDeviceNotFoundDialog: (_) async {}, // No dialog during silent periodic reconnect
            context: context,
            loading: false, // Don't show global loading indicator for periodic reconnect
          ).timeout(timeout);
        } on TimeoutException {
          // Silent timeout for periodic reconnect
        } catch (_) {
          // Silent failure for periodic reconnect
        }
      }
    });
  }

  void _showSnackBar(String message, {Color? backgroundColor, Duration duration = const Duration(seconds: 2)}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          message,
          style: TextStyle(color: whiteColor), // White text on snackbar
        ),
        backgroundColor: backgroundColor,
        duration: duration,
        behavior: SnackBarBehavior.floating, // Looks nicer
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
      ));
    }
  }

  /* -- page list -- */
  late final List<Widget> _pages = [
    const HomePage(),
    const SettingsPage(),
  ];

  /* ═════════════════ permissions ═════════════════ */
  Future<bool> _requestBluetoothPermissions() async {
    final status = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse, // Required for scanning on some Android versions
    ].request();

    return status.values.every((s) => s.isGranted);
  }

  Future<bool> _ensureBluetoothAndPermissions() async {
    if (!await _requestBluetoothPermissions()) {
      _showSnackBar('Bluetooth permissions are required.', backgroundColor: disconnectedColor);
      return false;
    }

    final bt = fb.FlutterBluetoothSerial.instance;
    bool btOn = await bt.isEnabled ?? false;
    if (!btOn) {
      // Prompt user to enable Bluetooth
      bool? enabled = await bt.requestEnable();
      btOn = enabled ?? false;
      if (!btOn) {
        _showSnackBar('Please enable Bluetooth.', backgroundColor: disconnectedColor);
        return false;
      }
    }
    return true;
  }

  bool _looksLikePrinter(fb.BluetoothDevice d) {
    final nm = (d.name ?? '').toLowerCase();
    const hints = [
      'printer', 'tvs', 'zebra', 'bixolon', 'hprt', 'epson', 'star',
      'intermec', 'rongta', 'gprinter', 'sewoo', 'xprinter', 'pos', 'p-touch'
    ];
    return hints.any(nm.contains);
  }

  /* ═════════════════ SCALE dialog (classic BT) ═════════════════ */
  Future<void> _showScaleDialog() async {
    if (!await _ensureBluetoothAndPermissions()) return;

    List<fb.BluetoothDiscoveryResult> bonded = [];
    List<fb.BluetoothDiscoveryResult> unbonded = [];
    StreamSubscription<fb.BluetoothDiscoveryResult>? sub;
    bool discovering = false;
    String query = '';

    Future<void> startScan(VoidCallback refresh) async {
      bonded.clear();
      unbonded.clear();
      discovering = true;
      refresh(); // Refresh dialog to show 'discovering' state

      final seen = <String>{};
      try {
        final paired = await fb.FlutterBluetoothSerial.instance.getBondedDevices();
        for (var d in paired) {
          if (seen.add(d.address)) {
            bonded.add(fb.BluetoothDiscoveryResult(device: d, rssi: 0));
          }
        }
      } catch (e) {
        _showSnackBar('Error getting paired devices: $e', backgroundColor: disconnectedColor);
      }
      refresh(); // Refresh to show already bonded devices

      sub?.cancel(); // Cancel any previous subscription
      sub = fb.FlutterBluetoothSerial.instance.startDiscovery().listen((r) {
        if (!seen.add(r.device.address)) return; // Only add if not seen
        (r.device.isBonded ? bonded : unbonded).add(r);
        refresh(); // Update list as devices are discovered
      }, onDone: () {
        discovering = false;
        refresh();
      }, onError: (e) {
        _showSnackBar('Error during discovery: $e', backgroundColor: disconnectedColor);
        discovering = false;
        refresh();
      });

      Future.delayed(const Duration(seconds: 8), () { // Increased scan duration
        if (discovering) { // If discovery is still active after timeout
          sub?.cancel();
          discovering = false;
          refresh();
        }
      });
    }

    await startScan(() {}); // Initial scan

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final connectedAddr = bluetoothController.scaleDevice?.address;

          final bondedShown = bonded
              .where((r) =>
          r.device.address != connectedAddr &&
              ('${r.device.name ?? ''} ${r.device.address}')
                  .toLowerCase()
                  .contains(query.toLowerCase()))
              .toList();

          final unbondedShown = unbonded
              .where((r) =>
          r.device.address != connectedAddr &&
              ('${r.device.name ?? ''} ${r.device.address}')
                  .toLowerCase()
                  .contains(query.toLowerCase()))
              .toList();

          List<Widget> tiles = [];

          if (bluetoothController.scaleConnected &&
              bluetoothController.scaleDevice != null) {
            final d = bluetoothController.scaleDevice!;
            tiles.add(ListTile(
              leading:
              Icon(Icons.bluetooth_connected, color: vibrantGreen), // Using vibrantGreen
              title: Text(d.name ?? d.address, style: TextStyle(color: charcoalColor)), // Using charcoalColor
              subtitle: Text('Connected', style: TextStyle(color: vibrantGreen)), // Using vibrantGreen
              trailing: IconButton(
                icon: Icon(Icons.link_off, color: disconnectedColor),
                onPressed: () async {
                  await bluetoothController.disconnectDevice(forScale: true);
                  await Future.delayed(const Duration(milliseconds: 200));
                  await startScan(() => setDlg(() {}));
                },
              ),
            ));
            tiles.add(Divider(color: charcoalColor.withOpacity(0.3))); // Using charcoalColor
          }

          if (bondedShown.isNotEmpty) {
            tiles.add(Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text('Paired Devices',
                  style: TextStyle(fontWeight: FontWeight.bold, color: charcoalColor)), // Using charcoalColor
            ));
            tiles.addAll(
                bondedShown.map((r) => _scaleTile(r, sub, setDlg)));
          }
          if (unbondedShown.isNotEmpty) {
            if (bondedShown.isNotEmpty) {
              tiles.add(Divider(color: charcoalColor.withOpacity(0.3))); // Using charcoalColor
            }
            tiles.add(Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text('Available Devices',
                  style: TextStyle(fontWeight: FontWeight.bold, color: charcoalColor)), // Using charcoalColor
            ));
            tiles.addAll(
                unbondedShown.map((r) => _scaleTile(r, sub, setDlg)));
          }
          if (tiles.isEmpty) {
            tiles.add(discovering
                ? Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(vibrantGreen))) // Using vibrantGreen
                : Center(child: Text('No devices found', style: TextStyle(color: charcoalColor)))); // Using charcoalColor
          }

          return AlertDialog(
            backgroundColor: whiteColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Select Scale', style: TextStyle(color: charcoalColor, fontWeight: FontWeight.bold)), // Using charcoalColor
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            content: SingleChildScrollView(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search…',
                      prefixIcon: Icon(Icons.search, color: charcoalColor), // Using charcoalColor
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: charcoalColor.withOpacity(0.5)), // Using charcoalColor
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: vibrantGreen, width: 2), // Using vibrantGreen
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    ),
                    style: TextStyle(color: charcoalColor), // Using charcoalColor
                    onChanged: (v) => setDlg(() => query = v),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 250,
                    width: double.maxFinite,
                    child: ListView(children: tiles),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => startScan(() => setDlg(() {})),
                style: TextButton.styleFrom(
                  backgroundColor: charcoalColor, // Using charcoalColor
                  foregroundColor: whiteColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                child: const Text('REFRESH', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  sub?.cancel(); // Ensure subscription is cancelled on dialog close
                },
                style: TextButton.styleFrom(
                  foregroundColor: charcoalColor, // Using charcoalColor
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                child: const Text('CANCEL', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );

    await sub?.cancel();
  }


  Widget _scaleTile(fb.BluetoothDiscoveryResult r, StreamSubscription? sub,
      void Function(void Function()) setDlg) {
    final d = r.device;
    return ListTile(
      leading: Icon(Icons.bluetooth, color: charcoalColor), // Using charcoalColor
      title: Text(d.name ?? d.address, style: TextStyle(color: charcoalColor)), // Using charcoalColor
      subtitle: Text(d.address, style: TextStyle(color: lightTextColor)),
      onTap: () async {
        sub?.cancel(); // Cancel subscription immediately on tap
        Navigator.pop(context); // Pop dialog immediately
        _showSnackBar('Connecting to ${d.name ?? d.address}...', backgroundColor: charcoalColor, duration: const Duration(seconds: 3)); // Using charcoalColor
        try {
          await bluetoothController.connectToDevice(d, forScale: true, context: context).timeout(const Duration(seconds: 8)); // Increased timeout
          if (!mounted) return;
          _showSnackBar(
            'Connected to ${d.name ?? d.address}',
            backgroundColor: vibrantGreen, // Using vibrantGreen
          );
        } on TimeoutException {
          _showSnackBar(
            'Connection to ${d.name ?? d.address} timed out.',
            backgroundColor: disconnectedColor,
          );
        } catch (_) {
          _showSnackBar(
            'Unable to connect to ${d.name ?? d.address}',
            backgroundColor: disconnectedColor,
          );
        }
      },
    );
  }


  /* ═════════════════ PRINTER dialog (classic BT) ═════════════════ */
  Future<void> _showPrinterDialog() async {
    if (!await _ensureBluetoothAndPermissions()) return;

    List<fb.BluetoothDiscoveryResult> bonded = [];
    List<fb.BluetoothDiscoveryResult> unbonded = [];
    StreamSubscription<fb.BluetoothDiscoveryResult>? sub;
    bool discovering = false; // Need to manage discovering state for the dialog

    String query = '';

    Future<void> scan(VoidCallback refresh) async {
      bonded.clear();
      unbonded.clear();
      discovering = true;
      refresh(); // Show discovering indicator

      final seen = <String>{};
      try {
        final paired = await fb.FlutterBluetoothSerial.instance.getBondedDevices();
        for (var d in paired) {
          if (seen.add(d.address)) {
            bonded.add(fb.BluetoothDiscoveryResult(device: d, rssi: 0));
          }
        }
      } catch (e) {
        _showSnackBar('Error getting paired devices: $e', backgroundColor: disconnectedColor);
      }
      refresh();

      sub?.cancel();
      sub = fb.FlutterBluetoothSerial.instance.startDiscovery().listen((r) {
        if (!seen.add(r.device.address)) return;
        (r.device.isBonded ? bonded : unbonded).add(r);
        refresh();
      }, onDone: () {
        discovering = false;
        refresh();
      }, onError: (e) {
        _showSnackBar('Error during discovery: $e', backgroundColor: disconnectedColor);
        discovering = false;
        refresh();
      });

      Future.delayed(const Duration(seconds: 8), () { // Increased scan duration
        if (discovering) {
          sub?.cancel();
          discovering = false;
          refresh();
        }
      });
    }

    await scan(() {}); // Initial scan

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final connectedAddr = bluetoothController.printerDevice?.address;

          final printers = <fb.BluetoothDiscoveryResult>[];
          final others = <fb.BluetoothDiscoveryResult>[];

          for (final r in [...bonded, ...unbonded]) {
            if (r.device.address == connectedAddr) continue;
            (_looksLikePrinter(r.device) ? printers : others).add(r);
          }

          final low = query.toLowerCase();
          final printersShown = printers
              .where((r) =>
              ('${r.device.name ?? ''} ${r.device.address}')
                  .toLowerCase()
                  .contains(low))
              .toList();
          final othersShown = others
              .where((r) =>
              ('${r.device.name ?? ''} ${r.device.address}')
                  .toLowerCase()
                  .contains(low))
              .toList();

          List<Widget> rows = [];

          if (bluetoothController.printerConnected &&
              bluetoothController.printerDevice != null) {
            final d = bluetoothController.printerDevice!;
            rows.add(ListTile(
              leading:
              Icon(Icons.local_printshop_outlined, color: vibrantGreen), // Using vibrantGreen
              title: Text(d.name ?? d.address, style: TextStyle(color: charcoalColor)), // Using charcoalColor
              subtitle: Text('Connected', style: TextStyle(color: vibrantGreen)), // Using vibrantGreen
              trailing: IconButton(
                icon: Icon(Icons.link_off, color: disconnectedColor),
                onPressed: () async {
                  await bluetoothController.disconnectDevice(forScale: false);
                  await Future.delayed(const Duration(milliseconds: 200));
                  await scan(() => setDlg(() {}));
                },
              ),
            ));
            rows.add(Divider(color: charcoalColor.withOpacity(0.3))); // Using charcoalColor
          }

          if (printersShown.isNotEmpty) {
            rows.add(Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text('Detected Printers',
                  style: TextStyle(fontWeight: FontWeight.bold, color: charcoalColor)), // Using charcoalColor
            ));
            rows.addAll(printersShown.map((r) => _printerTile(r, sub, setDlg)));
            rows.add(Divider(color: charcoalColor.withOpacity(0.3))); // Using charcoalColor
          }

          if (othersShown.isNotEmpty) {
            rows.add(Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text('Other Devices',
                  style: TextStyle(fontWeight: FontWeight.bold, color: charcoalColor)), // Using charcoalColor
            ));
            rows.addAll(othersShown.map((r) => _printerTile(r, sub, setDlg)));
          }

          if (rows.isEmpty) {
            rows.add(discovering
                ? Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(vibrantGreen))) // Using vibrantGreen
                : Center(child: Text('No devices found', style: TextStyle(color: charcoalColor)))); // Using charcoalColor
          }

          return AlertDialog(
            backgroundColor: whiteColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Select Printer', style: TextStyle(color: charcoalColor, fontWeight: FontWeight.bold)), // Using charcoalColor
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            content: SingleChildScrollView(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search…',
                      prefixIcon: Icon(Icons.search, color: charcoalColor), // Using charcoalColor
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: charcoalColor.withOpacity(0.5)), // Using charcoalColor
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: vibrantGreen, width: 2), // Using vibrantGreen
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    ),
                    style: TextStyle(color: charcoalColor), // Using charcoalColor
                    onChanged: (v) => setDlg(() => query = v),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 250,
                    width: double.maxFinite,
                    child: ListView(children: rows),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => scan(() => setDlg(() {})),
                style: TextButton.styleFrom(
                  backgroundColor: charcoalColor, // Using charcoalColor
                  foregroundColor: whiteColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                child: const Text('REFRESH', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  sub?.cancel(); // Ensure subscription is cancelled on dialog close
                },
                style: TextButton.styleFrom(
                  foregroundColor: charcoalColor, // Using charcoalColor
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                child: const Text('CANCEL', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );

    await sub?.cancel();
  }

  Widget _printerTile(fb.BluetoothDiscoveryResult r, StreamSubscription? sub,
      void Function(void Function()) setDlg) {
    final d = r.device;
    final isPrinter = _looksLikePrinter(d);
    return ListTile(
      leading:
      Icon(isPrinter ? Icons.local_printshop_outlined : Icons.bluetooth, color: charcoalColor), // Using charcoalColor
      title: Text(d.name ?? d.address, style: TextStyle(color: charcoalColor)), // Using charcoalColor
      subtitle: Text(d.address, style: TextStyle(color: lightTextColor)),
      onTap: () async {
        sub?.cancel(); // Cancel subscription immediately on tap
        Navigator.pop(context); // Pop dialog immediately
        _showSnackBar('Connecting to ${d.name ?? d.address}...', backgroundColor: charcoalColor, duration: const Duration(seconds: 3)); // Using charcoalColor
        try {
          await bluetoothController.connectToDevice(d, forScale: false, context: context).timeout(const Duration(seconds: 8)); // Increased timeout
          if (!mounted) return;
          _showSnackBar(
            'Connected to ${d.name ?? d.address}',
            backgroundColor: vibrantGreen, // Using vibrantGreen
          );
        } on TimeoutException {
          _showSnackBar(
            'Connection to ${d.name ?? d.address} timed out.',
            backgroundColor: disconnectedColor,
          );
        } catch (_) {
          _showSnackBar(
            'Unable to connect to ${d.name ?? d.address}',
            backgroundColor: disconnectedColor,
          );
        }
      },
    );
  }

  /* ═════════════════ BOTTOM NAV BAR ═════════════════ */
  Widget _navButton(IconData icon, int idx) {
    final sel = _tab == idx;
    return GestureDetector(
      onTap: () => setState(() => _tab = idx),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220), // Slightly faster animation for simple color change
        curve: Curves.easeInOut, // Smooth animation curve
        width: 54, // Fixed width
        height: 54, // Fixed height
        decoration: BoxDecoration(
          color: sel ? whiteColor : charcoalColor, // Selected: White, Unselected: Charcoal
          borderRadius: BorderRadius.circular(16), // Fixed rounded corners
          // No boxShadow for selected state
        ),
        child: Icon(icon, size: 28, color: sel ? charcoalColor : whiteColor), // Icon color inverse of background
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        extendBody: true, // Allows the body to extend behind the bottom nav bar
        appBar: AppBar(
          toolbarHeight: 70.0, // Set a specific height
          backgroundColor: Colors.transparent, // Make AppBar transparent to show Container's color
          elevation: 0, // Remove AppBar's default shadow
          flexibleSpace: Container(
            decoration: BoxDecoration(
              color: charcoalColor, // AppBar background charcoal
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(30), // Apply rounded bottom corners
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 15,
                  spreadRadius: 2,
                  offset: const Offset(0, 5), // Shadow pointing downwards
                ),
              ],
            ),
          ),
          title: Padding( // Added padding for content
            padding: const EdgeInsets.only(left: 8.0), // Adjust left padding as needed
            child: Row(
              mainAxisSize: MainAxisSize.min, // Keep the row compact
              children: [
                Icon(Icons.monitor_weight, color: whiteColor, size: 25), // Smaller icon size
                const SizedBox(width: 8), // Adjusted spacing
                Text(
                  'SMART SCALE',
                  style: TextStyle(
                    color: whiteColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 20, // Smaller font size
                    fontFamily: 'Montserrat',
                  ),
                ),
              ],
            ),
          ),
          centerTitle: false, // Set to false to align to start
          actions: [
            AnimatedBuilder(
              animation: bluetoothController,
              builder: (_, __) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) {
                  return ScaleTransition(scale: animation, child: child);
                },
                child: IconButton(
                  key: ValueKey(bluetoothController.printerConnected),
                  icon: Icon(Icons.print,
                      size: 25, // Smaller icon size
                      color: bluetoothController.printerConnected
                          ? vibrantGreen // Using vibrantGreen
                          : disconnectedColor),
                  tooltip: bluetoothController.printerConnected
                      ? 'Printer connected'
                      : 'Tap to connect printer',
                  onPressed: _showPrinterDialog,
                ),
              ),
            ),
            AnimatedBuilder(
              animation: bluetoothController,
              builder: (_, __) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) {
                  return ScaleTransition(scale: animation, child: child);
                },
                child: IconButton(
                  key: ValueKey(bluetoothController.scaleConnected),
                  icon: Icon(Icons.scale,
                      size: 25, // Smaller icon size
                      color: bluetoothController.scaleConnected
                          ? vibrantGreen // Using vibrantGreen
                          : disconnectedColor),
                  tooltip: bluetoothController.scaleConnected
                      ? 'Scale connected'
                      : 'Tap to connect scale',
                  onPressed: _showScaleDialog,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: IndexedStack(index: _tab, children: _pages),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
          decoration: BoxDecoration(
            color: charcoalColor, // Bottom nav bar background charcoal
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(30),
              topRight: Radius.circular(30),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 15,
                spreadRadius: 2,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _navButton(Icons.home_filled, 0),
              _navButton(Icons.settings, 1),
            ],
          ),
        ),
      ),
    );
  }
}