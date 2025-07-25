// lib/controllers/bluetooth_controller.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helper/loader_helper.dart';

class BluetoothController extends ChangeNotifier {
  /* ───────── Connections ───────── */
  BluetoothConnection? _scaleConn;
  BluetoothConnection? _printerConn;

  BluetoothDevice? _scaleDevice;
  BluetoothDevice? _printerDevice;

  Stream<List<int>>? _scaleInput;

  /* ───────── Live callback ───────── */
  /// Assign in UI (HomePage) to get weight lines pushed automatically.
  void Function(String value)? onWeightReceived;

  /* ───────── Public getters ───────── */
  bool get scaleConnected   => _scaleConn?.isConnected   ?? false;
  bool get printerConnected => _printerConn?.isConnected ?? false;

  BluetoothDevice? get scaleDevice   => _scaleDevice;
  BluetoothDevice? get printerDevice => _printerDevice;

  static const _scaleKey = 'last_scale_address';
  static const _printerKey = 'last_printer_address';




  /* ═════════════════ CONNECTION ═════════════════ */
  Future<void> autoReconnectDevicesSequentially({
    required Future<void> Function(bool forScale) onDeviceNotFoundDialog,
    required BuildContext context,
    bool loading = true,
  }) async {
    if (loading) {
      await _withBluetoothLoader(context, () async {
        await _attemptReconnect(onDeviceNotFoundDialog, context);
      });
    } else {
      await _attemptReconnect(onDeviceNotFoundDialog, context, loading: false); // ← no loader here
    }
  }

// Moved common reconnect logic to a separate private method
  Future<void> _attemptReconnect(
      Future<void> Function(bool forScale) onDeviceNotFoundDialog,
      BuildContext context,
      {bool loading = true}
      ) async {
    final prefs = await SharedPreferences.getInstance();
    final devices = await FlutterBluetoothSerial.instance.getBondedDevices();

    final scaleAddress = prefs.getString(_scaleKey);
    if (scaleAddress != null) {
      final scaleDevice = devices.firstWhere(
            (d) => d.address == scaleAddress,
        orElse: () => BluetoothDevice(address: '', name: '', type: BluetoothDeviceType.unknown),
      );
      if (scaleDevice.address.isNotEmpty) {
        try {
          await connectToDevice(scaleDevice, forScale: true, context: context, loading: loading);
        } catch (_) {
          await onDeviceNotFoundDialog(true);
        }
      } else {
        await onDeviceNotFoundDialog(true);
      }
    } else {
      await onDeviceNotFoundDialog(true);
    }

    final printerAddress = prefs.getString(_printerKey);
    if (printerAddress != null) {
      final printerDevice = devices.firstWhere(
            (d) => d.address == printerAddress,
        orElse: () => BluetoothDevice(address: '', name: '', type: BluetoothDeviceType.unknown),
      );
      if (printerDevice.address.isNotEmpty) {
        try {
          await connectToDevice(printerDevice, forScale: false, context: context, loading: loading);
        } catch (_) {
          await onDeviceNotFoundDialog(false);
        }
      } else {
        await onDeviceNotFoundDialog(false);
      }
    } else {
      await onDeviceNotFoundDialog(false);
    }
  }


  Future<T> _withBluetoothLoader<T>(
      BuildContext context,
      Future<T> Function() operation,
      ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: LoaderHelper.bluetoothLoader(),
      ),
    );

    try {
      return await operation();
    } finally {
      if (context.mounted) Navigator.of(context).pop(); // Close loader
    }
  }




  /* ───────────── Modified connectToDevice() ───────────── */
  Future<void> connectToDevice(
      BluetoothDevice d, {
        required bool forScale,
        required BuildContext context,
        bool loading = true,
      }) async {
    operation() async {
      try {
        final conn = await BluetoothConnection.toAddress(d.address);
        final prefs = await SharedPreferences.getInstance();

        if (forScale) {
          await _scaleConn?.close();
          _scaleConn = conn;
          _scaleDevice = d;
          _scaleInput = conn.input!.asBroadcastStream();
          prefs.setString(_scaleKey, d.address);
          _startScaleListener();
        } else {
          await _printerConn?.close();
          _printerConn = conn;
          _printerDevice = d;
          prefs.setString(_printerKey, d.address);
        }

        notifyListeners();
      } catch (e) {
        debugPrint('BT connect error: $e');
        await disconnectDevice(forScale: forScale);
        rethrow;
      }
    }

    if (loading) {
      await _withBluetoothLoader(context, operation).timeout(Duration(seconds: 5));
    } else {
      await operation().timeout(Duration(seconds: 5));
    }
  }



  Future<void> disconnectDevice({required bool forScale}) async {
    if (forScale) {
      await _scaleConn?.close();
      _scaleConn = null;
      _scaleDevice = null;
      _scaleInput = null;
      notifyListeners();

    } else {
      _printerConn?.close();
      await( _printerConn?.close())?.timeout(Duration(milliseconds: 200));
      _printerConn = null;
      _printerDevice = null;
      notifyListeners();

    }
    notifyListeners();
  }

  /* ═════════════════ SCALE helpers ═════════════════ */
  void _startScaleListener() {
    if (_scaleInput == null) return;

    _scaleInput!.listen((data) {
      final txt = String.fromCharCodes(data).trim();
      // crude filter: only forward pure numbers or numbers with dot
      if (RegExp(r'^\d+(\.\d+)?$').hasMatch(txt)) {
        onWeightReceived?.call(txt);
      }
    }, onError: (e) {
      debugPrint('Scale stream error: $e');
    });
  }

  /// One‑shot read (3 s timeout) – returns entire line.
  Future<String?> readScaleLine() async {
    if (!scaleConnected || _scaleInput == null) return null;

    final completer = Completer<String?>();
    final buffer = StringBuffer();
    late StreamSubscription sub;

    sub = _scaleInput!.listen((data) {
      final txt = String.fromCharCodes(data);
      buffer.write(txt);
      if (txt.contains('\n')) {
        sub.cancel();
        completer.complete(buffer.toString().trim());
      }
    }, onError: (e) {
      if (!completer.isCompleted) completer.completeError(e);
    }, onDone: () {
      if (!completer.isCompleted) completer.complete(null);
    });

    return completer.future
        .timeout(const Duration(seconds: 3), onTimeout: () {
      sub.cancel();
      return null;
    });
  }

  /* ═════════════════ STATIC LABEL PRINT ═════════════════ */
  Future<void> printLabel({
    required String itemName,
    required String quality,
    required String operatorName,
    required String bobbin,
    required int machineNo,
    required int micron,
    required int meters,
    required String gross,
    required String boxTare,
    required String bobbinTare,
    required String net,
    required String mfgDate,
  }) async {
    if (!printerConnected) throw 'Printer not connected';

    final parts    = net.split('.');
    final intPart  = parts[0].padLeft(2, '0');
    final fracPart = (parts.length > 1 ? parts[1] : '')
        .padRight(3, '0')
        .substring(0, 3);

    final barcode = '!105$intPart!100 $fracPart';
    final hrText  = '$intPart $fracPart';

    final tspl = '''
SIZE 99.5 mm, 75.1 mm\r
DIRECTION 0,0\r
CLS\r
TEXT 10,30,"0",0,1,1,"$itemName"\r
TEXT 10,70,"0",0,1,1,"$quality"\r
TEXT 10,110,"0",0,1,1,"Gross: $gross kg"\r
TEXT 10,150,"0",0,1,1,"Net: $net kg"\r
BARCODE 10,190,"128",80,1,0,2,2,"$barcode"\r
TEXT 10,280,"0",0,1,1,"$hrText"\r
PRINT 1,1\r
''';

    _printerConn!.output.add(Uint8List.fromList(utf8.encode(tspl)));
    await _printerConn!.output.allSent;
  }

  // Add this method
  Future<void> sendRawTSPL(String content) async {
    if (!printerConnected) throw 'Printer not connected';
    _printerConn!.output.add(Uint8List.fromList(utf8.encode(content)));
    await _printerConn!.output.allSent;
  }
  void sendTSPL(Uint8List bytes) {
    if (!printerConnected) return;
    _printerConn!.output.add(bytes);
  }
  Future<void> printRawTspl(String tspl) async {
    if (!printerConnected) throw 'Printer not connected';
    _printerConn!.output.add(Uint8List.fromList(utf8.encode(tspl)));
    await _printerConn!.output.allSent;
  }


  /* ═════════════════ DYNAMIC LABEL PRINT ═════════════════ */
  /// Builds a TSPL label at runtime from form‑field pairs.
  Future<void> sendDynamicTSPL({
    required List<Map<String, String>> fields,
    required String gross,
    required String tareBox,
    required String tareBobbin,
    required String net,
  }) async {
    if (!printerConnected) throw 'Printer not connected';

    // Basic vertical layout – 30 px per line starting at y=30.
    final StringBuffer buf = StringBuffer();
    buf.writeln('SIZE 76 mm,50 mm');
    buf.writeln('GAP 2 mm,0');
    buf.writeln('DIRECTION 0');
    buf.writeln('CLS');

    int y = 20;
    for (var entry in fields) {
      final lbl = entry['label']?.trim();
      final val = entry['value']?.trim();
      if (lbl == null || val == null || lbl.isEmpty) continue;
      buf.writeln('TEXT 10,$y,"0",0,1,1,"$lbl: $val"');
      y += 30;
    }

    buf.writeln('TEXT 10,$y,"0",0,1,1,"Gross: $gross kg"');   y += 30;
    buf.writeln('TEXT 10,$y,"0",0,1,1,"Tare Box: $tareBox kg"'); y += 30;
    buf.writeln('TEXT 10,$y,"0",0,1,1,"Tare Bobbin: $tareBobbin kg"'); y += 30;
    buf.writeln('TEXT 10,$y,"0",0,1,1,"Net: $net kg"');         y += 40;

    // Simple barcode (itemName‑netWeight)
    final String barcodeData = '${fields.firstWhere(
          (e) => e['label']?.toLowerCase() == 'item',
      orElse: () => {'value': 'ITEM'},
    )['value']}-${net}kg';

    buf.writeln('BARCODE 10,$y,"128",80,1,0,2,2,"$barcodeData"');
    y += 90;

    buf.writeln('PRINT 1,1');

    _printerConn!.output.add(Uint8List.fromList(utf8.encode(buf.toString())));
    await _printerConn!.output.allSent;
  }
}

/* ───────── Global singleton for legacy code ───────── */
final bluetoothController = BluetoothController();
