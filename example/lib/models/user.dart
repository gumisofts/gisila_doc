/// Domain models used by the example controllers. They are plain Dart
/// classes - gisila_doc inspects their constructor parameters to
/// derive JSON schemas, and uses [User.toJson] / [CreateUser.fromJson]
/// at runtime.
library;

class User {
  User({
    required this.id,
    required this.name,
    required this.email,
    this.age,
    this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
        age: json['age'] as int?,
        createdAt: json['createdAt'] == null
            ? null
            : DateTime.parse(json['createdAt'] as String),
      );

  final String id;
  final String name;
  final String email;
  final int? age;
  final DateTime? createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'email': email,
        if (age != null) 'age': age,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      };
}

class CreateUser {
  CreateUser({required this.name, required this.email, this.age});

  factory CreateUser.fromJson(Map<String, dynamic> json) => CreateUser(
        name: json['name'] as String,
        email: json['email'] as String,
        age: json['age'] as int?,
      );

  final String name;
  final String email;
  final int? age;
}
