// lib/navbar.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

import 'bluetooth_controller.dart';
import 'printer_controller.dart';
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

  StreamSubscription<List<ScanResult>>? _bleSub;
  bool _bleScanRunning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 100));
      await _showBleDialog();               // BLE dialog first
      if (mounted) await _showPrinterDialog();
    });
  }

  /* ═════════════════ BLE SCALE DIALOG (with BT‑ON check) ═════════════════ */
  Future<void> _showBleDialog() async {
    if (!await _blePerms()) return;

    /* ---- 1) Ensure Bluetooth is ON ---- */
    final btSerial = FlutterBluetoothSerial.instance;
    if (!(await btSerial.isEnabled ?? false)) {
      await btSerial.requestEnable(); // prompts user
      if (!(await btSerial.isEnabled ?? false)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bluetooth is required to connect to scale')),
        );
        return;
      }
    }
    // Double‑check with FlutterBluePlus (sanity)
    if (!await FlutterBluePlus.isOn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please turn on Bluetooth')),
      );
      return;
    }
    /* ----------------------------------- */


    List<ScanResult> results = [];
    bool scanning = true;
    String query = '';

    Future<void> _startBleScan(VoidCallback refresh) async {
      if (_bleScanRunning) return;
      _bleScanRunning = true;
      scanning = true;
      results.clear();
      refresh();

      await FlutterBluePlus.stopScan();
      await _bleSub?.cancel();

      final seen = <String>{};
      bool stopped = false;
      void _stop() async {
        if (stopped) return;
        stopped = true;
        scanning = false;
        _bleScanRunning = false;
        await FlutterBluePlus.stopScan();
        await _bleSub?.cancel();
        refresh();
      }

      final timeout = Timer(const Duration(seconds: 4), _stop);

      _bleSub = FlutterBluePlus.scanResults.listen((list) {
        bool firstHit = false;
        for (final r in list) {
          final dev = r.device;
          final isConnected = bluetoothController.connected &&
              dev.remoteId == bluetoothController.device?.remoteId;
          if (isConnected) continue;
          if (!bluetoothController.isEspDevice(r)) continue;
          if (!seen.add(dev.remoteId.str)) continue;
          results.add(r);
          firstHit = true;
        }
        refresh();
        if (firstHit) {
          timeout.cancel();
          _stop();
        }
      });
      await FlutterBluePlus.startScan();
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool scanQueued = false;
        return StatefulBuilder(
          builder: (ctx, setDlg) {
            if (!scanQueued) {
              scanQueued = true;
              WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _startBleScan(() => setDlg(() {})));
            }

            final filtered = results.where((r) {
              final dev = r.device;
              final isConnected = bluetoothController.connected &&
                  dev.remoteId == bluetoothController.device?.remoteId;
              if (isConnected) return false;
              final text =
              '${dev.platformName} ${dev.remoteId.str}'.toLowerCase();
              return text.contains(query.toLowerCase());
            }).toList();

            return AlertDialog(
              scrollable: true,
              title: const Text('Select BLE Scale'),
              contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              content: SingleChildScrollView(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(ctx).viewInsets.bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search…',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (v) => setDlg(() => query = v),
                    ),
                    const SizedBox(height: 10),
                    if (bluetoothController.connected)
                      ListTile(
                        leading: const Icon(Icons.bluetooth_connected,
                            color: Colors.green),
                        title:
                        Text(bluetoothController.device!.platformName),
                        subtitle: const Text('Connected'),
                        trailing: IconButton(
                          icon: const Icon(Icons.link_off, color: Colors.red),
                          onPressed: () async {
                            await bluetoothController.disconnect();
                            setDlg(() {});
                          },
                        ),
                      ),
                    SizedBox(
                      height: 250,
                      width: double.maxFinite,
                      child: scanning
                          ? const Center(child: CircularProgressIndicator())
                          : filtered.isEmpty
                          ? const Center(child: Text('No devices found'))
                          : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final d = filtered[i].device;
                          return ListTile(
                            leading: const Icon(Icons.bluetooth),
                            title: Text(d.platformName.isNotEmpty
                                ? d.platformName
                                : d.remoteId.str),
                            onTap: () async {
                              await FlutterBluePlus.stopScan();
                              try {
                                await d.connect();
                                bluetoothController.setDevice(d);
                                if (!mounted) return;
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(
                                    content: Text(
                                        'Connected to ${d.platformName}')));
                              } catch (_) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(const SnackBar(
                                    content: Text(
                                        'Unable to connect')));
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => _startBleScan(() => setDlg(() {})),
                  child: const Text('REFRESH'),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF0E1B4B),
                    foregroundColor: Colors.white,
                  )
                ),
              ],
            );
          },
        );
      },
    );

    await FlutterBluePlus.stopScan();
    await _bleSub?.cancel();
  }/* ═════════════════ CLASSIC‑BT PRINTER DIALOG (stop on first, no duplicates) ═════════════════ */
  Future<void> _showPrinterDialog() async {
    if (!await _classicPerms()) return;

    final bt = FlutterBluetoothSerial.instance;
    if (!(await bt.isEnabled ?? false)) {
      await bt.requestEnable();
      if (!(await bt.isEnabled ?? false)) return;
    }

    List<BluetoothDiscoveryResult> bondedResults = [];
    List<BluetoothDiscoveryResult> unbondedResults = [];
    bool discovering = false;
    StreamSubscription<BluetoothDiscoveryResult>? sub;
    String query = '';

    Future<void> startScan(VoidCallback refresh) async {
      bondedResults.clear();
      unbondedResults.clear();
      discovering = true;
      refresh();

      final seenAddr = <String>{};

      /* bonded devices first */
      try {
        final bonded = await bt.getBondedDevices();
        bondedResults = bonded
            .where((d) => seenAddr.add(d.address)) // skip dup address
            .map((d) => BluetoothDiscoveryResult(device: d, rssi: 0))
            .toList();
      } catch (_) {}
      refresh();

      sub?.cancel();
      sub = bt.startDiscovery().listen((r) async {
        if (!seenAddr.add(r.device.address)) return; // duplicate

        final list = r.device.isBonded ? bondedResults : unbondedResults;
        list.add(r);
        refresh();

        /* stop discovery after first NEW printer found */
        discovering = false;
        await sub?.cancel();
      });

      /* hard timeout 6 s */
      Future.delayed(const Duration(seconds: 6), () async {
        if (discovering) {
          discovering = false;
          await sub?.cancel();
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
          // Get current connected device (if any)
          final connectedDevice = printerController.device;
          final connectedAddr = connectedDevice?.address;

          // Filter devices excluding connected one
          final bondedShown = bondedResults.where((r) {
            return r.device.address != connectedAddr &&
                '${r.device.name ?? ''} ${r.device.address}'
                    .toLowerCase()
                    .contains(query.toLowerCase());
          }).toList();

          final unbondedShown = unbondedResults.where((r) {
            return r.device.address != connectedAddr &&
                '${r.device.name ?? ''} ${r.device.address}'
                    .toLowerCase()
                    .contains(query.toLowerCase());
          }).toList();

          List<Widget> rows = [];


          // Only show connected device if printerController says we're connected
          if (printerController.connected && connectedDevice != null) {
            rows.add(ListTile(
              leading: const Icon(Icons.bluetooth_connected, color: Colors.green),
              title: Text(connectedDevice.name ?? connectedDevice.address),
              subtitle: const Text('Connected'),
              trailing: IconButton(
                icon: const Icon(Icons.link_off, color: Colors.red),
                onPressed: () async {
                  // Immediately disable the button to prevent multiple taps
                  setDlg(() {}); // First refresh to disable button

                  // Get the device before disconnecting
                  final device = printerController.device;
                  if (device == null) return;

                  // Perform the disconnect
                  await printerController.disconnect();

                  // Create discovery result for the device
                  final result = BluetoothDiscoveryResult(
                    device: device,
                    rssi: 0,
                  );


                  // Add to appropriate list based on bonding status
                  if (device.isBonded) {
                    bondedResults.insert(0, result);
                  } else {
                    unbondedResults.insert(0, result);
                  }

                  // Force complete UI update
                  setDlg(() {});
                },
              ),
            ));
            rows.add(const Divider());
          }

          if (bondedShown.isNotEmpty) {
            rows.add(const Text('Paired',
                style: TextStyle(fontWeight: FontWeight.bold)));
            rows.addAll(bondedShown.map((r) => _printerTile(r, sub, setDlg)));
            rows.add(const Divider());
          }

          if (unbondedShown.isNotEmpty) {
            rows.add(const Text('Available',
                style: TextStyle(fontWeight: FontWeight.bold)));
            rows.addAll(unbondedShown.map((r) => _printerTile(r, sub, setDlg)));
          }

          if (rows.isEmpty && !discovering) {
            rows.add(const Center(child: Text('No devices found')));
          } else if (discovering && rows.isEmpty) {
            rows.add(const Center(child: CircularProgressIndicator()));
          }

          return AlertDialog(
            scrollable: true,
            title: const Text('Bluetooth Printers'),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            content: SingleChildScrollView(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search…',
                      prefixIcon: Icon(Icons.search),
                    ),
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
                onPressed: () => startScan(() => setDlg(() {})),
                child: const Text('REFRESH'),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF0E1B4B),
                    foregroundColor: Colors.white,
                  )
              ),
            ],
          );
        },
      ),
    );

    await sub?.cancel();
  }

  Widget _printerTile(BluetoothDiscoveryResult r,
      StreamSubscription? sub, void Function(void Function()) setDlg) {
    final d = r.device;
    return ListTile(
      leading: const Icon(Icons.bluetooth),
      title: Text(d.name ?? d.address),
      subtitle: Text(d.address),
      onTap: () async {
        await sub?.cancel();
        Navigator.pop(context);
        final ok = await printerController.connect(d);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
            Text(ok ? 'Connected to ${d.name ?? d.address}' : 'Unable to connect')));
      },
    );
  }

  /* ───────── permissions helpers ───────── */
  Future<bool> _blePerms() async => await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.locationWhenInUse,
  ].request().then((m) => m.values.every((s) => s.isGranted));

  Future<bool> _classicPerms() async => await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.locationWhenInUse,
  ].request().then((m) => m.values.every((s) => s.isGranted));


  /* ───────── nav‑button widget ───────── */
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
        child: Icon(icon,
            size: 28, color: sel ? const Color(0xFF0E1B4B) : Colors.white),
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
            animation: printerController,
            builder: (_, __) => IconButton(
              icon: Icon(Icons.print,
                  color:
                  printerController.connected ? Colors.green : Colors.red),
              tooltip: printerController.connected
                  ? 'Printer connected'
                  : 'Tap to connect printer',
              onPressed: _showPrinterDialog,
            ),
          ),
          AnimatedBuilder(
            animation: bluetoothController,
            builder: (_, __) => IconButton(
              icon: Icon(
                Icons.scale,
                color: bluetoothController.connected
                    ? Colors.green
                    : Colors.red,
              ),
              tooltip: bluetoothController.connected
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
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(50),
            topRight: Radius.circular(50),
          ),
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