import 'package:shelf/shelf.dart';
import 'package:gisila_doc/gisila_doc.dart';
import 'package:shelf_router/shelf_router.dart';

import '../models/user.dart';

part 'users_controller.g.dart';

@Controller('/users', ['Users'])
class UsersController {
  UsersController();

  final Map<String, User> _store = <String, User>{};

  /// Returns every user, optionally paginated.
  @Get(
    '/',
    summary: 'List users',
    description: 'Returns a (paginated) list of all known users.',
  )
  Future<List<User>> listUsers({int? limit, int? offset}) async {
    final all = _store.values.toList();
    final start = offset ?? 0;
    final end = limit == null ? all.length : (start + limit).clamp(0, all.length);
    return all.sublist(start.clamp(0, all.length), end);
  }

  /// Fetches a single user by id.
  @Get('/{id}', summary: 'Fetch a user', operationId: 'getUserById')
  @ApiResponse(404, description: 'User not found')
  Future<Response> getUser(String id) async {
    final user = _store[id];
    if (user == null) {
      return Response.notFound('{"error":"user not found"}',
          headers: const {'content-type': 'application/json'});
    }
    return jsonResponse(user);
  }

  /// Creates a new user.
  @Post('/', summary: 'Create a user')
  Future<User> createUser(CreateUser body) async {
    final id = (_store.length + 1).toString();
    final user = User(
      id: id,
      name: body.name,
      email: body.email,
      age: body.age,
      createdAt: DateTime.now().toUtc(),
    );
    _store[id] = user;
    return user;
  }

  /// Deletes a user.
  @Delete('/{id}', summary: 'Delete a user')
  Future<void> deleteUser(String id) async {
    _store.remove(id);
  }
}
