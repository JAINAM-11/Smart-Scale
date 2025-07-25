import 'dart:async';
import 'package:flutter/material.dart';
import 'bluetooth_controller.dart';

class Home extends StatefulWidget {
  const Home({Key? key}) : super(key: key);
  @override
  HomeState createState() => HomeState();
}

class HomeState extends State<Home> with AutomaticKeepAliveClientMixin<Home> {
  @override
  bool get wantKeepAlive => true;

  double? grossWeight;
  String itemName = '', quality = '', operatorName = '', bobbin = '';
  int machineNo = 0, micron = 0, meter = 0;
  DateTime? selectedDate;

  final _formKey = GlobalKey<FormState>();
  final _itemCtrl = TextEditingController();
  final _qualityCtrl = TextEditingController();
  final _operatorNameCtrl = TextEditingController();
  final _bobbinCtrl = TextEditingController();
  final _machineNoCtrl = TextEditingController();
  final _micronCtrl = TextEditingController();
  final _meterCtrl = TextEditingController();
  final _boxTareCtrl = TextEditingController();
  final _bobbinTareCtrl = TextEditingController();
  final _mfgDateCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    selectedDate = now;
    _mfgDateCtrl.text =
    "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }

  @override
  void dispose() {
    _itemCtrl.dispose();
    _qualityCtrl.dispose();
    _operatorNameCtrl.dispose();
    _bobbinCtrl.dispose();
    _machineNoCtrl.dispose();
    _micronCtrl.dispose();
    _meterCtrl.dispose();
    _boxTareCtrl.dispose();
    _bobbinTareCtrl.dispose();
    _mfgDateCtrl.dispose();
    super.dispose();
  }

  double get _netWeight {
    final box = double.tryParse(_boxTareCtrl.text) ?? 0;
    final bobbinW = double.tryParse(_bobbinTareCtrl.text) ?? 0;
    return (grossWeight ?? 0) - box - bobbinW;
  }

  double? _parseWeight(String s) =>
      double.tryParse(s.replaceAll(RegExp('[^0-9+\\-.]'), ''));

  Future<void> _readWeight() async {
    if (!bluetoothController.scaleConnected) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Scale not connected')));
      return;
    }

    try {
      final line = await bluetoothController.readScaleLine();
      final v = _parseWeight(line ?? '');
      if (v == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Invalid data')));
        return;
      }
      setState(() => grossWeight = v);
    } catch (_) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Unable to read weight')));
    }
  }

  Future<void> _print() async {
    if (!bluetoothController.printerConnected) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No printer connected')));
      return;
    }

    try {
      await bluetoothController.printLabel(
        itemName: itemName,
        quality: quality,
        operatorName: operatorName,
        bobbin: bobbin,
        machineNo: machineNo,
        micron: micron,
        meters: meter,
        gross: grossWeight?.toStringAsFixed(3) ?? '0.000',
        boxTare: _boxTareCtrl.text,
        bobbinTare: _bobbinTareCtrl.text,
        net: _netWeight.toStringAsFixed(3),
        mfgDate: _mfgDateCtrl.text,
      );
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Printed')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Print failed')));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // keepalive

    /* ---- unchanged UI layout (only controller calls swapped) ---- */
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
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
                        _buildTextField(_itemCtrl, 'Item Name',
                            onChanged: (v) => itemName = v),
                        _buildTextField(_qualityCtrl, 'Quality',
                            onChanged: (v) => quality = v),
                        _buildTextField(_operatorNameCtrl, 'Operator Name',
                            onChanged: (v) => operatorName = v),
                        _buildTextField(_machineNoCtrl, 'Machine No',
                            keyboard: TextInputType.number,
                            onChanged: (v) =>
                            machineNo = int.tryParse(v) ?? 0),
                        _buildTextField(_micronCtrl, 'Micron',
                            keyboard: TextInputType.number,
                            onChanged: (v) => micron = int.tryParse(v) ?? 0),
                        _buildTextField(_meterCtrl, 'Meters',
                            keyboard: TextInputType.number,
                            onChanged: (v) => meter = int.tryParse(v) ?? 0),
                        _buildTextField(_bobbinCtrl, 'Bobbin',
                            onChanged: (v) => bobbin = v),
                        _buildDatePickerField(context),
                        _buildTextField(_boxTareCtrl, 'Tare Box Weight',
                            keyboard: TextInputType.number,
                            suffix: 'kg',
                            onChanged: (_) => setState(() {})),
                        _buildTextField(_bobbinTareCtrl, 'Tare Bobbin Weight',
                            keyboard: TextInputType.number,
                            suffix: 'kg',
                            onChanged: (_) => setState(() {})),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Gross Weight:',
                                style: TextStyle(
                                    color: Color(0xFF0E1B4B),
                                    fontWeight: FontWeight.bold)),
                            Text('${(grossWeight ?? 0).toStringAsFixed(3)} kg',
                                style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600)),
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
                          onPressed: _print,
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
        ),
      ),
    );
  }

  /* -------------- helpers keep UI identical -------------- */
  Widget _buildTextField(TextEditingController ctrl, String label,
      {String? suffix,
        TextInputType? keyboard,
        void Function(String)? onChanged}) =>
      Column(
        children: [
          TextFormField(
            controller: ctrl,
            keyboardType: keyboard,
            decoration: InputDecoration(
              labelText: label,
              suffixText: suffix,
              border: const OutlineInputBorder(),
            ),
            onChanged: onChanged,
          ),
          const SizedBox(height: 20),
        ],
      );

  Widget _buildDatePickerField(BuildContext context) => Column(
    children: [
      TextFormField(
        controller: _mfgDateCtrl,
        readOnly: true,
        decoration: const InputDecoration(
          labelText: 'MFG Date',
          suffixIcon: Icon(Icons.calendar_today),
          border: OutlineInputBorder(),
        ),
        onTap: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: selectedDate ?? now,
            firstDate: DateTime(now.year - 5),
            lastDate: now,
          );
          if (picked != null) {
            setState(() {
              selectedDate = picked;
              _mfgDateCtrl.text =
              "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
            });
          }
        },
      ),
      const SizedBox(height: 20),
    ],
  );
}
