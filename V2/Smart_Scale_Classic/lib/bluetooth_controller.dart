// lib/bluetooth_controller.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

class BluetoothController extends ChangeNotifier {
  /* ───────── Scale connection ───────── */
  BluetoothConnection? _scaleConn;
  BluetoothDevice?      _scaleDevice;
  Stream<List<int>>?    _scaleInput;

  /* ───────── Printer connection ─────── */
  BluetoothConnection? _printerConn;
  BluetoothDevice?     _printerDevice;

  /* ───────── Public getters ─────────── */
  bool get scaleConnected   => _scaleConn?.isConnected   ?? false;
  bool get printerConnected => _printerConn?.isConnected ?? false;

  BluetoothDevice? get scaleDevice   => _scaleDevice;
  BluetoothDevice? get printerDevice => _printerDevice;

  /* ═════════════════ CONNECTIONS ═════════════════ */
  Future<void> connectToDevice(BluetoothDevice d, {required bool forScale}) async {
    try {
      final conn = await BluetoothConnection.toAddress(d.address);

      if (forScale) {
        await _scaleConn?.close();
        _scaleConn   = conn;
        _scaleDevice = d;
        _scaleInput  = conn.input!.asBroadcastStream();
      } else {
        await _printerConn?.close();
        _printerConn   = conn;
        _printerDevice = d;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('BT connect error: $e');
      await disconnectDevice(forScale: forScale);
      rethrow;
    }
  }

  Future<void> disconnectDevice({required bool forScale}) async {
    if (forScale) {
      await _scaleConn?.close();
      _scaleConn = null;
      _scaleDevice = null;
      notifyListeners();
    } else {
      await _printerConn?.close();
      _printerConn = null;
      _printerDevice = null;
      notifyListeners();
    }
    notifyListeners();
    
  }


  /* ═════════════════ SCALE  helpers ═════════════════ */
  Future<String?> readScaleLine() async {
    if (!scaleConnected || _scaleInput == null) return null;

    final buffer    = StringBuffer();
    final completer = Completer<String?>();

    late StreamSubscription<List<int>> sub;
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

    return completer.future.timeout(const Duration(seconds: 3), onTimeout: () {
      sub.cancel();
      return null;
    });
  }

  /* ═════════════════ PRINT helper ═══════════════════ */
  Future<void> printLabel({
    required String itemName,
    required String quality,
    required String operatorName,
    required String bobbin,
    required int    machineNo,
    required int    micron,
    required int    meters,
    required String gross,
    required String boxTare,
    required String bobbinTare,
    required String net,
    required String mfgDate,
  }) async {
    if (!printerConnected) throw 'Printer not connected';

    /* barcode parts from net‑weight */
    final parts    = net.split('.');
    final intPart  = parts[0].padLeft(2, '0');
    final fracPart = (parts.length > 1 ? parts[1] : '')
        .padRight(3, '0')
        .substring(0, 3);

    final barcode  = '!105$intPart!100 $fracPart';
    final hrText   = '$intPart $fracPart';

    /* ----- TSPL label template ----- */
    final tspl = '''
SIZE 99.5 mm, 75.1 mm\r
DIRECTION 0,0\r
REFERENCE 0,0\r
OFFSET 0 mm\r
SET TEAR ON\r
CLS\r
CODEPAGE 1252\r
ERASE 10,506,773,76\r
TEXT 782,581,"0",180,43,23,"PACKING SLIP"\r
REVERSE 10,506,773,76\r
TEXT 748,498,"ROMAN.TTF",180,1,9,"ITEM"\r
TEXT 387,498,"ROMAN.TTF",180,1,9,"QUALITY"\r
TEXT 775,471,"0",180,10,11,"$itemName"\r
TEXT 349,470,"0",180,10,11,"$quality"\r
TEXT 762,426,"ROMAN.TTF",180,1,9,"OPERATOR NAME"\r
TEXT 499,426,"ROMAN.TTF",180,1,9,"MACHINE NO"\r
TEXT 762,397,"0",180,10,11,"$operatorName"\r
TEXT 435,397,"0",180,10,11,"$machineNo"\r
TEXT 299,426,"ROMAN.TTF",180,1,9,"MICRON"\r
TEXT 276,397,"0",180,10,11,"$micron"\r
TEXT 762,340,"ROMAN.TTF",180,1,9,"METERS"\r
TEXT 507,340,"ROMAN.TTF",180,1,9,"BOBBIN"\r
TEXT 300,340,"ROMAN.TTF",180,1,9,"MFG DATE"\r
TEXT 762,311,"0",180,10,11,"$meters"\r
TEXT 507,311,"0",180,10,11,"$bobbin"\r
TEXT 306,311,"0",180,10,11,"$mfgDate"\r
TEXT 775,266,"ROMAN.TTF",180,1,9,"GROSS WEIGHT"\r
TEXT 532,266,"ROMAN.TTF",180,1,9,"TARE BOX WEIGHT"\r
TEXT 276,266,"0",180,9,9,"TARE BOBBIN WEIGHT"\r
TEXT 762,237,"0",180,10,11,"$gross Kg"\r
TEXT 499,237,"0",180,10,11,"$boxTare Kg"\r
TEXT 260,237,"0",180,10,11,"$bobbinTare Kg"\r
TEXT 757,177,"ROMAN.TTF",180,1,9,"NET WEIGHT"\r
CODEPAGE 1253\r
TEXT 733,148,"0",180,10,11,"$net Kg"\r
BARCODE 562,179,"128M",49,0,180,3,6,"$barcode"\r
CODEPAGE 1252\r
TEXT 443,125,"ROMAN.TTF",180,1,9,"$hrText"\r
BAR 0,87,794,9\r
TEXT 541,81,"0",180,13,14,"S.R.METALIZERS"\r
TEXT 515,39,"0",180,10,11,"Tel 0201‑2361000"\r
PRINT 1,1\r
''';

    _printerConn!.output.add(Uint8List.fromList(utf8.encode(tspl)));
    await _printerConn!.output.allSent;
  }

  /* ═════════════════ Helper: scale name filter ═════════════════ */

}

final bluetoothController = BluetoothController();
