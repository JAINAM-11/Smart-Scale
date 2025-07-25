import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

class PrinterController extends ChangeNotifier {
  BluetoothConnection? _conn;
  BluetoothDevice? _dev;
  bool _isBtOn = true;

  PrinterController() {
    FlutterBluetoothSerial.instance.onStateChanged().listen((st) {
      final on = st == BluetoothState.STATE_ON;
      if (on != _isBtOn) {
        _isBtOn = on;
        notifyListeners();
      }
    });
    FlutterBluetoothSerial.instance.state
        .then((st) => _isBtOn = st == BluetoothState.STATE_ON);
  }

  bool get connected => _isBtOn && (_conn?.isConnected ?? false);
  BluetoothDevice? get device => _dev;

  Future<bool> connect(BluetoothDevice d) async {
    try {
      _conn = await BluetoothConnection.toAddress(d.address);
      _dev = d;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Printer connect error: $e');
      await disconnect();
      return false;
    }
  }

  Future<void> disconnect() async {
    final local = _conn;
    _conn = null;
    _dev = null;
    notifyListeners();
    try {
      await local?.close();
    } catch (_) {}
  }

  Future<void> printLabel({
    required String itemName,
    required String gross,
    required String boxTare,
    required String bobbinTare,
    required String net,
  }) async {
    if (!connected) throw 'Printer not connected';

    // — Split net weight into integer and fractional parts for barcode
    final parts = net.split('.');
    final intPart = parts[0].padLeft(2, '0');
    final fracPart = (parts.length > 1 ? parts[1] : '')
        .padRight(3, '0')
        .substring(0, 3);

    final barcodeData = '!105$intPart!100 $fracPart';
    final hrText = '$intPart $fracPart';

    final tspl = '''
SIZE 99.5 mm, 75.1 mm\r
DIRECTION 0,0\r
REFERENCE 0,0\r
OFFSET 0 mm\r
SET PEEL OFF\r
SET CUTTER OFF\r
SET PARTIAL_CUTTER OFF\r
SET TEAR ON\r
CLS\r
CODEPAGE 1252\r
ERASE 10,506,773,76\r
TEXT 782,581,"0",180,43,23,"PACKING SLIP"\r
REVERSE 10,506,773,76\r
TEXT 748,498,"ROMAN.TTF",180,1,9,"ITEM"\r
TEXT 387,498,"ROMAN.TTF",180,1,9,"QUALITY"\r
TEXT 775,471,"0",180,10,11,"$itemName"\r
TEXT 349,470,"0",180,10,11,"50/33 BCH 211 A (DG"\r
TEXT 762,426,"ROMAN.TTF",180,1,9,"OPERATOR NAME"\r
TEXT 499,426,"ROMAN.TTF",180,1,9,"MACHINE NO"\r
TEXT 762,397,"0",180,10,11,"B5 RAMVILAS"\r
TEXT 435,397,"0",180,10,11,"6"\r
TEXT 299,426,"ROMAN.TTF",180,1,9,"MICRON"\r
TEXT 276,397,"0",180,10,11,"13"\r
TEXT 762,340,"ROMAN.TTF",180,1,9,"METERS"\r
TEXT 507,340,"ROMAN.TTF",180,1,9,"BOBBIN"\r
TEXT 300,340,"ROMAN.TTF",180,1,9,"MFG DATE"\r
TEXT 762,311,"0",180,10,11,"22000"\r
TEXT 507,311,"0",180,10,11,"[RB]64"\r
TEXT 306,311,"0",180,10,11,"23/03/2021"\r
TEXT 775,266,"ROMAN.TTF",180,1,9,"GROSS WEIGHT"\r
TEXT 532,266,"ROMAN.TTF",180,1,9,"TARE BOX WEIGHT"\r
TEXT 276,266,"0",180,9,9,"TARE BOBBIN WEIGHT"\r
TEXT 762,237,"0",180,10,11,"$gross Kg"\r
TEXT 499,237,"0",180,10,11,"$boxTare Kg"\r
TEXT 260,237,"0",180,10,11,"$bobbinTare Kg"\r
TEXT 757,177,"ROMAN.TTF",180,1,9,"NET WEIGHT"\r
CODEPAGE 1253\r
TEXT 733,148,"0",180,10,11,"$net Kg"\r
BARCODE 562,179,"128M",49,0,180,3,6,"$barcodeData"\r
CODEPAGE 1252\r
TEXT 443,125,"ROMAN.TTF",180,1,9,"$hrText"\r
BAR 0,87,794,9\r
TEXT 541,81,"0",180,13,14,"S.R.METALIZERS"\r
TEXT 515,39,"0",180,10,11,"Tale 0201-2361000"\r
PRINT 1,1\r
''';

    _conn!.output.add(Uint8List.fromList(utf8.encode(tspl)));
    await _conn!.output.allSent;
  }
}

final printerController = PrinterController();
