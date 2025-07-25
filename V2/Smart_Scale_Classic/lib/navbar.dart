// lib/navbar.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart' as fb;
import 'package:permission_handler/permission_handler.dart';

import 'bluetooth_controller.dart';
import 'home.dart';
import 'settings.dart';

class NavBar extends StatefulWidget {
  const NavBar({super.key});
  @override
  State<NavBar> createState() => _NavBarState();
}

class _NavBarState extends State<NavBar> {
  final _homeKey = GlobalKey<HomeState>();
  int _tab = 0;
  late final _pages = [Home(key: _homeKey), const Setting()];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 100));
      await _showBleDialog();
      if (mounted) await _showPrinterDialog();
    });
  }

  /* ────────────────────────── helpers ────────────────────────── */

  Future<bool> _classicPerms() async => await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.locationWhenInUse,
  ].request().then((m) => m.values.every((s) => s.isGranted));

  bool _looksLikePrinter(fb.BluetoothDevice d) {
    final nm = (d.name ?? '').toLowerCase();
    const hints = [
      'printer',
      'tvs',
      'zebra',
      'bixolon',
      'hprt',
      'epson',
      'star',
      'intermec',
      'rongta',
      'gprinter',
      'sewoo',
      'xprinter'
    ];
    return hints.any(nm.contains);
  }

  /* ═════════════════ SCALE DIALOG ═════════════════ */
  Future<void> _showBleDialog() async {
    if (!await _classicPerms()) return;

    final bt = fb.FlutterBluetoothSerial.instance;
    bool btOn = await bt.isEnabled ?? false;
    if (!btOn) {
      await bt.requestEnable();
      btOn = await bt.isEnabled ?? false;
      if (!btOn) return;
    }

    List<fb.BluetoothDiscoveryResult> bonded = [];
    List<fb.BluetoothDiscoveryResult> unbonded = [];
    StreamSubscription<fb.BluetoothDiscoveryResult>? sub;
    bool discovering = false;
    String query = '';

    Future<void> startScan(VoidCallback refresh) async {
      bonded.clear();
      unbonded.clear();
      discovering = true;
      refresh();

      final seen = <String>{};

      try {
        final paired = await bt.getBondedDevices();
        for (var d in paired) {
          if (seen.add(d.address)) {
            bonded.add(fb.BluetoothDiscoveryResult(device: d, rssi: 0));
          }
        }
      } catch (_) {}
      refresh();

      sub?.cancel();
      sub = bt.startDiscovery().listen((r) {
        if (!seen.add(r.device.address)) return;
        (r.device.isBonded ? bonded : unbonded).add(r);
        discovering = false;
        sub?.cancel();
        refresh();
      });

      Future.delayed(const Duration(seconds: 6), () {
        if (discovering) {
          discovering = false;
          sub?.cancel();
          refresh();
        }
      });
    }

    await startScan(() {});

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

          /* connected row */
          if (bluetoothController.scaleConnected &&
              bluetoothController.scaleDevice != null) {
            final d = bluetoothController.scaleDevice!;
            tiles.add(ListTile(
              leading:
              const Icon(Icons.bluetooth_connected, color: Colors.green),
              title: Text(d.name ?? d.address),
              subtitle: const Text('Connected'),
              trailing: IconButton(
                icon: const Icon(Icons.link_off, color: Colors.red),
                onPressed: () async {
                  await bluetoothController.disconnectDevice(forScale: true);
                  await Future.delayed(const Duration(milliseconds: 200));
                  await startScan(() => setDlg(() {}));
                },
              ),

            ));
            tiles.add(const Divider());
          }

          if (bondedShown.isNotEmpty) {
            tiles.add(const Text('Paired',
                style: TextStyle(fontWeight: FontWeight.bold)));
            tiles.addAll(
                bondedShown.map((r) => _scaleTile(r, sub, setDlg)));
          }
          if (unbondedShown.isNotEmpty) {
            tiles.add(const Divider());
            tiles.add(const Text('Available',
                style: TextStyle(fontWeight: FontWeight.bold)));
            tiles.addAll(
                unbondedShown.map((r) => _scaleTile(r, sub, setDlg)));
          }
          if (tiles.isEmpty) {
            tiles.add(discovering
                ? const Center(child: CircularProgressIndicator())
                : const Center(child: Text('No devices found')));
          }

          return AlertDialog(
            scrollable: true,
            title: const Text('Select Scale'),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            content: SingleChildScrollView(
              padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: const InputDecoration(
                        hintText: 'Search…',
                        prefixIcon: Icon(Icons.search)),
                    onChanged: (v) => setDlg(() => query = v),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                      height: 250,
                      width: double.maxFinite,
                      child: ListView(children: tiles)),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => startScan(() => setDlg(() {})),
                child: const Text('Refresh'),
                style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF0E1B4B),
                    foregroundColor: Colors.white),
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
      leading: const Icon(Icons.bluetooth),
      title: Text(d.name ?? d.address),
      subtitle: Text(d.address),
      onTap: () async {
        await sub?.cancel();
        Navigator.pop(context);
        try {
          await bluetoothController.connectToDevice(d, forScale: true);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Connected to ${d.name ?? d.address}')));
        } catch (_) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Unable to connect')));
        }
      },
    );
  }

  /* ═════════════════ PRINTER DIALOG ═════════════════ */
  Future<void> _showPrinterDialog() async {
    if (!await _classicPerms()) return;

    final bt = fb.FlutterBluetoothSerial.instance;
    bool btOn = await bt.isEnabled ?? false;
    if (!btOn) {
      await bt.requestEnable();
      btOn = await bt.isEnabled ?? false;
      if (!btOn) return;
    }

    List<fb.BluetoothDiscoveryResult> bonded = [];
    List<fb.BluetoothDiscoveryResult> unbonded = [];
    StreamSubscription<fb.BluetoothDiscoveryResult>? sub;
    bool discovering = false;
    String query = '';

    Future<void> scan(VoidCallback refresh) async {
      bonded.clear();
      unbonded.clear();
      discovering = true;
      refresh();

      final seen = <String>{};
      try {
        final paired = await bt.getBondedDevices();
        for (var d in paired) {
          if (seen.add(d.address)) {
            bonded.add(fb.BluetoothDiscoveryResult(device: d, rssi: 0));
          }
        }
      } catch (_) {}
      refresh();

      sub?.cancel();
      sub = bt.startDiscovery().listen((r) {
        if (!seen.add(r.device.address)) return;
        (r.device.isBonded ? bonded : unbonded).add(r);
        discovering = false;
        sub?.cancel();
        refresh();
      });

      Future.delayed(const Duration(seconds: 6), () {
        if (discovering) {
          discovering = false;
          sub?.cancel();
          refresh();
        }
      });
    }

    await scan(() {});

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
              const Icon(Icons.bluetooth_connected, color: Colors.green),
              title: Text(d.name ?? d.address),
              subtitle: const Text('Connected'),
              trailing: IconButton(
                icon: const Icon(Icons.link_off, color: Colors.red),
                onPressed: () async {
                  await bluetoothController.disconnectDevice(forScale: false);
                  await Future.delayed(const Duration(milliseconds: 200));
                  await scan(() => setDlg(() {}));
                },
              ),

            ));
            rows.add(const Divider());
          }

          if (printersShown.isNotEmpty) {
            rows.add(const Text('Detected Printers Devices',
                style: TextStyle(fontWeight: FontWeight.bold)));
            rows.addAll(
                printersShown.map((r) => _printerTile(r, sub, setDlg)));
            rows.add(const Divider());
          }

          if (othersShown.isNotEmpty) {
            rows.add(const Text('Other Devices',
                style: TextStyle(fontWeight: FontWeight.bold)));
            rows.addAll(
                othersShown.map((r) => _printerTile(r, sub, setDlg)));
          }

          if (rows.isEmpty) {
            rows.add(discovering
                ? const Center(child: CircularProgressIndicator())
                : const Center(child: Text('No devices found')));
          }

          return AlertDialog(
            scrollable: true,
            title: const Text('Select Printer'),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            content: SingleChildScrollView(
              padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: const InputDecoration(
                        hintText: 'Search…',
                        prefixIcon: Icon(Icons.search)),
                    onChanged: (v) => setDlg(() => query = v),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                      height: 250,
                      width: double.maxFinite,
                      child: ListView(children: rows)),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => scan(() => setDlg(() {})),
                child: const Text('Refresh'),
                style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF0E1B4B),
                    foregroundColor: Colors.white),
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
      leading: Icon(isPrinter ? Icons.print : Icons.bluetooth,
          color: isPrinter ? Colors.blueAccent[100] : null),
      title: Text(d.name ?? d.address),
      subtitle: Text(d.address),
      onTap: () async {
        await sub?.cancel();
        Navigator.pop(context);
        try {
          await bluetoothController.connectToDevice(d, forScale: false);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Connected to ${d.name ?? d.address}')));
        } catch (_) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Unable to connect')));
        }
      },
    );
  }

  /* ───────────────────── NAV BAR ───────────────────── */

  Widget _navButton(IconData icon, int idx) {
    final sel = _tab == idx;
    return GestureDetector(
      onTap: () => setState(() => _tab = idx),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: sel ? Colors.white : const Color(0xFF0E1B4B),
          borderRadius: BorderRadius.circular(16),
        ),
        child:
        Icon(icon, size: 28, color: sel ? const Color(0xFF0E1B4B) : Colors.white),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: const Text('Smart Scale'),
        centerTitle: true,
        actions: [
          AnimatedBuilder(
            animation: bluetoothController,
            builder: (_, __) => IconButton(
              icon: Icon(Icons.print,
                  color: bluetoothController.printerConnected
                      ? Colors.green
                      : Colors.red),
              tooltip: bluetoothController.printerConnected
                  ? 'Printer connected'
                  : 'Tap to connect printer',
              onPressed: _showPrinterDialog,
            ),
          ),
          AnimatedBuilder(
            animation: bluetoothController,
            builder: (_, __) => IconButton(
              icon: Icon(Icons.scale,
                  color: bluetoothController.scaleConnected
                      ? Colors.green
                      : Colors.red),
              tooltip: bluetoothController.scaleConnected
                  ? 'Scale connected'
                  : 'Tap to connect scale',
              onPressed: _showBleDialog,
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _tab, children: _pages),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
        decoration: const BoxDecoration(
          color: Color(0xFF0E1B4B),
          borderRadius:
          BorderRadius.only(topLeft: Radius.circular(50), topRight: Radius.circular(50)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _navButton(Icons.home, 0),
            _navButton(Icons.settings, 1),
          ],
        ),
      ),
    ),
  );
}
