library;

import 'package:gisila_doc/gisila_doc.dart';

import '../models/user.dart';

class UserService extends Service {
  static final _store = <String, User>{};

  Future<List<User>> list({int? limit, int? offset}) async {
    final all = _store.values.toList();
    final start = offset ?? 0;
    final end =
        limit == null ? all.length : (start + limit).clamp(0, all.length);
    return all.sublist(start.clamp(0, all.length), end);
  }

  Future<User> getById(String id) async {
    final user = _store[id];
    if (user == null) throw NotFound('User "$id" not found');
    return user;
  }

  Future<User> create({
    required String name,
    required String email,
    int? age,
  }) async {
    final id = (_store.length + 1).toString();
    final user = User(
      id: id,
      name: name,
      email: email,
      age: age,
      createdAt: DateTime.now().toUtc(),
    );
    _store[id] = user;
    return user;
  }

  Future<void> delete(String id) async {
    if (_store.remove(id) == null) throw NotFound('User "$id" not found');
  }
}
