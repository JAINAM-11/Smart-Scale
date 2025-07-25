// lib/bluetooth_controller.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BluetoothController extends ChangeNotifier {
  BluetoothDevice? _device;
  BluetoothDevice? get device => _device;
  bool get connected => _device != null;

  void setDevice(BluetoothDevice? d) {
    if (_device != d) {
      _device = d;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    await _device?.disconnect();
    _device = null;
    notifyListeners();
  }

  /* ═══ TRUE if the name looks like a scale ═══ */
  bool isEspDevice(ScanResult r) {
    // Prefer advertising names, fall back to device.platformName
    final name = (r.advertisementData.advName ??
        r.advertisementData.localName ??
        r.device.platformName)
        .toLowerCase();

    return name.contains('scale') ||
        name.contains('weight') ||
        name.contains('weighing') ||
        name.contains('esp');
  }

  /// Convenience “raw” scan for debugging
  Future<void> debugPrintOnce() async {
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
    FlutterBluePlus.scanResults.first.then((list) {
      for (final r in list) {
        debugPrint(
            '🔍  ${r.device.remoteId}  advName=${r.advertisementData.advName}  localName=${r.advertisementData.localName}  platformName=${r.device.platformName}');
      }
    });
  }
}

final bluetoothController = BluetoothController();
