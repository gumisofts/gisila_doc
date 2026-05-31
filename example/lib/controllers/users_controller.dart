import 'package:gisila_doc/gisila_doc.dart';

import '../forms/user_forms.dart';
import '../models/user.dart';
import '../services/user_service.dart';

part 'users_controller.g.dart';

@Controller('/users', ['Users'])
class UsersController {
  UsersController();

  /// Returns every user, optionally paginated.
  @Get(
    '/',
    summary: 'List users',
    description: 'Returns a (paginated) list of all known users.',
  )
  Future<List<User>> listUsers(
    UserService users, {
    int? limit,
    int? offset,
  }) =>
      users.list(limit: limit, offset: offset);

  /// Fetches a single user by id.
  @Get('/{id}', summary: 'Fetch a user', operationId: 'getUserById')
  @ApiResponse(404, description: 'User not found')
  Future<User> getUser(String id, UserService users) => users.getById(id);

  /// Creates a new user from a typed form.
  @Post(
    '/',
    summary: 'Create a user',
    config: RouteConfig(
      rateLimit: RateLimitConfig(requestsPerMinute: 60),
    ),
  )
  Future<User> createUser(CreateUserForm form, UserService users) {
    return users.create(
      name: form.name.value!,
      email: form.email.value!,
      age: form.age.value,
    );
  }

  /// Deletes a user.
  @Delete('/{id}', summary: 'Delete a user')
  Future<void> deleteUser(String id, UserService users) => users.delete(id);
}
