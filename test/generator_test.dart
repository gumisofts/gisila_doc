/// Runs the controller builder on a sample controller and checks the
/// OpenAPI code it generates for guards (DOC-01) and generics (DOC-02).
library gisila_doc.test.generator_test;

import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:gisila_doc/builder.dart';
import 'package:test/test.dart';

const _source = r'''
import 'package:gisila_doc/gisila_doc.dart';

part 'sample.g.dart';

class User {
  User({required this.name});
  final String name;
}

class Post {
  Post({required this.title});
  final String title;
}

class Page<T> {
  Page({required this.items, required this.total, this.next});
  final List<T> items;
  final int total;
  final T? next;
}

@Controller('/x')
@RequireAuth()
class SampleController {
  @Get('/users')
  Future<Page<User>> users() async => throw UnimplementedError();

  @Get('/posts')
  @Roles({'editor'})
  @Permissions({'posts.read'})
  Page<Post> posts() => throw UnimplementedError();

  @Get('/declared')
  @Roles({'admin'})
  @ApiResponse(403, description: 'Admins only')
  User declared() => throw UnimplementedError();

  @Get('/open')
  @Public()
  User open() => throw UnimplementedError();
}
''';

Future<String> _generate() async {
  final rw = TestReaderWriter(rootPackage: 'gisila_doc');
  await rw.testing.loadIsolateSources();
  String? generated;
  await testBuilder(
    controllerBuilder(BuilderOptions.empty),
    {'gisila_doc|lib/sample.dart': _source},
    rootPackage: 'gisila_doc',
    readerWriter: rw,
    outputs: {
      'gisila_doc|lib/sample.gisila_doc.g.part':
          decodedMatches(predicate<String>((s) {
        generated = s;
        return true;
      })),
    },
  );
  // GISILA_DOC_DUMP=<file> keeps the generated code for a closer look.
  final dump = Platform.environment['GISILA_DOC_DUMP'];
  if (dump != null) File(dump).writeAsStringSync(generated!);
  return generated!;
}

/// [code] without whitespace or trailing commas, so checks don't depend on
/// how dart_style wrapped the generated source.
String _squash(String code) => code
    .replaceAll(RegExp(r'\s+'), '')
    .replaceAll(',}', '}')
    .replaceAll(',]', ']')
    .replaceAll(',)', ')');

/// The squashed `Operation(...)` registered for [path].
String _operation(String code, String path) {
  final at = code.indexOf("/x$path';");
  expect(at, isNonNegative, reason: path);
  final start = code.indexOf('spec.putOperation(', at);
  return code.substring(start, code.indexOf('));', start));
}

/// The squashed `spec.putSchema('[name]', ...)` call.
String _schema(String code, String name) {
  final start = code.indexOf("spec.putSchema('$name',");
  expect(start, isNonNegative, reason: name);
  return code.substring(start, code.indexOf(');', start));
}

void main() {
  late String code;
  setUpAll(() async => code = _squash(await _generate()));

  group('DOC-01 auth in the spec', () {
    test('a class-level guard marks routes and adds a 401', () {
      final op = _operation(code, '/users');
      expect(op, contains('requiresAuth:true'));
      expect(op, contains("'401':ResponseSpec("));
      expect(op, contains('errorEnvelopeSchema'));
      expect(op, isNot(contains("'403'")));
    });

    test('roles and permissions are carried and add a 403', () {
      final op = _operation(code, '/posts');
      expect(op, contains("roles:<String>['editor']"));
      expect(op, contains("permissions:<String>['posts.read']"));
      expect(op, contains("'403':ResponseSpec("));
    });

    test("a route's own 403 is kept, not duplicated", () {
      final op = _operation(code, '/declared');
      expect("'403'".allMatches(op), hasLength(1));
      expect(op, contains("'Adminsonly'"));
    });

    test('@Public routes have no security', () {
      final op = _operation(code, '/open');
      expect(op, isNot(contains('requiresAuth')));
      expect(op, isNot(contains("'401'")));
    });
  });

  group('DOC-02 generic schemas', () {
    test('each instantiation gets its own component', () {
      expect(code, contains("spec.putSchema('Page_User',"));
      expect(code, contains("spec.putSchema('Page_Post',"));
      expect(code, isNot(contains("spec.putSchema('Page',")));
    });

    test('type parameters are substituted', () {
      final schema = _schema(code, 'Page_User');
      expect(
          schema,
          contains("'items':<String,Object?>{'type':'array',"
              "'items':<String,Object?>{r'\$ref':'#/components/schemas/User'}}"));
      // T? becomes a nullable reference to User.
      expect(
          schema,
          contains("'next':<String,Object?>{'anyOf':<Object?>["
              "<String,Object?>{r'\$ref':'#/components/schemas/User'}"));
      expect(schema, contains("'required':<String>['items','total']"));
      expect(
          _schema(code, 'Page_Post'), contains("'#/components/schemas/Post'"));
    });
  });
}
