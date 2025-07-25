import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'bluetooth_controller.dart';
import 'printer_controller.dart';

class Home extends StatefulWidget {
  const Home({Key? key}) : super(key: key);
  @override
  HomeState createState() => HomeState();
}

class HomeState extends State<Home> with AutomaticKeepAliveClientMixin<Home> {
  @override
  bool get wantKeepAlive => true;

  BluetoothDevice? connectedDevice;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;

  double? grossWeight;
  String itemName = '';

  final _formKey = GlobalKey<FormState>();
  final _itemCtrl = TextEditingController();
  final _boxTareCtrl = TextEditingController();
  final _bobbinTareCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _adapterSub = FlutterBluePlus.adapterState.listen((s) {
      if (s != BluetoothAdapterState.on) _handleDisconnect();
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _adapterSub?.cancel();
    connectedDevice?.disconnect();
    _itemCtrl.dispose();
    _boxTareCtrl.dispose();
    _bobbinTareCtrl.dispose();
    super.dispose();
  }

  void _listenToDevice(BluetoothDevice d) {
    _connSub?.cancel();
    _connSub = d.connectionState.listen((st) {
      if (st != BluetoothConnectionState.connected) _handleDisconnect();
    });
  }

  void _handleDisconnect() {
    _connSub?.cancel();
    bluetoothController.setDevice(null);
    setState(() {
      connectedDevice = null;
      grossWeight = null;
    });
  }

  String _ascii(List<int> b) =>
      String.fromCharCodes(b.takeWhile((x) => x != 0)).trim();

  double? _parse(String s) =>
      double.tryParse(s.replaceAll(RegExp('[^0-9+\-.]'), ''));

  Future<void> _readWeight() async {
    if (!bluetoothController.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scale Not connected')),
      );
      return;
    }

    final device = bluetoothController.device;
    if (device == null) return;
    try {
      final svcs = await device.discoverServices(timeout: 30);
      final svc = svcs.firstWhere((s) =>
          s.serviceUuid.toString().toLowerCase().endsWith('00ff'));
      final ch = svc.characteristics.firstWhere((c) =>
          c.characteristicUuid.toString().toLowerCase().endsWith('ff01'));
      final v = _parse(_ascii(await ch.read(timeout: 10)));
      if (v == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to read weight')),
        );
      }
      setState(() {
        connectedDevice = device;
        grossWeight = v;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to read weight')),
      );
      setState(() => grossWeight = null);
    }
  }

  double get _netWeight {
    final box = double.tryParse(_boxTareCtrl.text) ?? 0;
    final bobbin = double.tryParse(_bobbinTareCtrl.text) ?? 0;
    return (grossWeight ?? 0) - box - bobbin;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Card(
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            elevation: 6,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Text('Product Details',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _itemCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Item Name',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => itemName = v,
                    ),
                    const SizedBox(height: 20),

                    /// Tare Box Weight
                    TextFormField(
                      controller: _boxTareCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Tare Box Weight',
                        suffixText: 'kg',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || double.tryParse(v) == null)
                          ? 'Invalid'
                          : null,
                    ),
                    const SizedBox(height: 20),

                    /// Tare Bobbin Weight
                    TextFormField(
                      controller: _bobbinTareCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Tare Bobbin Weight',
                        suffixText: 'kg',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || double.tryParse(v) == null)
                          ? 'Invalid'
                          : null,
                    ),
                    const SizedBox(height: 20),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Gross Weight:',
                            style: TextStyle(
                                color: Color(0xFF0E1B4B),
                                fontWeight: FontWeight.bold)),
                        Text('${(grossWeight ?? 0).toStringAsFixed(3)} kg',
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w600)),
                        ElevatedButton(
                          onPressed: _readWeight,
                          child: const Text('Get'),
                        ),
                      ],
                    ),
                    const Divider(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Net Weight:',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('${_netWeight.toStringAsFixed(3)} kg',
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Colors.teal)),
                      ],
                    ),
                    const SizedBox(height: 30),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: const Color(0xFF0E1B4B),
                      ),
                      onPressed: () async {
                        if (!printerController.connected) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('No printer connected')));
                          return;
                        }

                        try {
                          await printerController.printLabel(
                            itemName: itemName,
                            gross:
                            grossWeight?.toStringAsFixed(3) ?? '0.000',
                            boxTare: _boxTareCtrl.text,
                            bobbinTare: _bobbinTareCtrl.text,
                            net: _netWeight.toStringAsFixed(3),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Printed')));
                        } catch (e) {
                          debugPrint('Print error: $e');
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Print failed')));
                        }
                      },
                      icon: const Icon(Icons.print),
                      label: const Text('Print'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
