library;

import 'package:gisila_doc/gisila_doc.dart';

class CreateUserForm extends Form {
  final name = StringField(name: 'name', required: true, maxLength: 100);
  final email = EmailField(name: 'email', required: true);
  final age = IntField(name: 'age', min: 0, max: 150);

  @override
  List<FormField<Object?>> collectFields() => [name, email, age];
}
