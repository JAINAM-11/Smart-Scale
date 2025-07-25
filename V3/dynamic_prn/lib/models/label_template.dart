class LabelTemplate {
  final String name;
  final Map<String, String> fields; // title → value
  final List<String> barcodeFields;
  final String separator;

  LabelTemplate({
    required this.name,
    required this.fields,
    required this.barcodeFields,
    required this.separator,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'fields': fields,
    'barcodeFields': barcodeFields,
    'separator': separator,
  };

  factory LabelTemplate.fromJson(Map<String, dynamic> json) => LabelTemplate(
    name: json['name'],
    fields: Map<String, String>.from(json['fields']),
    barcodeFields: List<String>.from(json['barcodeFields']),
    separator: json['separator'],
  );
}
