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

enum Color { red, green }

enum Coded {
  a;

  String toJson() => 'A';
}

class Palette {
  Palette({required this.main, this.accent, required this.tags,
      required this.all, required this.coded});
  final Color main;
  final Color? accent;
  final Set<String> tags;
  final Iterable<int> all;
  final Coded coded;
}

class Page<T> {
  Page({required this.items, required this.total, this.next});
  final List<T> items;
  final int total;
  final T? next;
}

class LoginForm extends Form {
  final email = EmailField(name: 'email', required: true);
  final password = PasswordField(name: 'password', required: true);

  @override
  List<FormField<Object?>> collectFields() => [email, password];
}

class AvatarForm extends Form {
  final caption = StringField(name: 'caption');
  final image = FileField(name: 'image', required: true);

  @override
  List<FormField<Object?>> collectFields() => [caption, image];
}

@Controller('/x')
@RequireAuth()
class SampleController {
  // `Post` is a model in this file, so these use @Put.
  @Put('/login')
  @Public()
  User login(LoginForm form) => throw UnimplementedError();

  @Put('/avatar')
  @Public()
  User avatar(AvatarForm form) => throw UnimplementedError();

  @Get('/item/<id>')
  @Public()
  @ApiResponse(400, description: 'Bad id')
  User item(@Path() int id) => throw UnimplementedError();

  @Get('/')
  @Public()
  User root() => throw UnimplementedError();

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

  @Get('/palette')
  @Public()
  Palette palette() => throw UnimplementedError();

  @Get('/search')
  @Public()
  User search({int? page}) => throw UnimplementedError();
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
  late String raw;
  late String code;
  setUpAll(() async {
    raw = await _generate();
    code = _squash(raw);
  });

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

  group('FW-09 only argument binding is wrapped', () {
    String handler(String path) {
      final at = code.indexOf("'\$prefix/x$path';");
      expect(at, isNonNegative, reason: path);
      return code.substring(at, code.indexOf('spec.putOperation(', at));
    }

    test('the controller call is outside the try', () {
      final h = handler('/search');
      final bindingEnds = h.indexOf('})();');
      // _squash drops the trailing comma, so check the record in [raw].
      expect(h, contains('final(page)=await(()async{try{'));
      expect(raw, contains('final (page,) = await'));
      expect(bindingEnds, isPositive);
      expect(h.indexOf('this.search(page:page)'), greaterThan(bindingEnds));
    });

    test('a route without parameters has no try at all', () {
      expect(handler('/open'), isNot(contains('try{')));
    });
  });

  group('DOC-03 enums and collections', () {
    test('an enum is a string with its names', () {
      final schema = _schema(code, 'Palette');
      expect(
          schema,
          contains("'main':<String,Object?>{'type':'string',"
              "'enum':<Object?>['red','green']}"));
      expect(
          schema,
          contains(
              "'accent':<String,Object?>{'type':<Object?>['string','null'],"
              "'enum':<Object?>['red','green',null]}"));
    });

    test('an enum with its own toJson() stays open', () {
      expect(_schema(code, 'Palette'), contains("'coded':<String,Object?>{}"));
    });

    test('Set and Iterable are arrays; a Set has unique items', () {
      final schema = _schema(code, 'Palette');
      expect(
          schema,
          contains("'tags':<String,Object?>{'type':'array',"
              "'items':<String,Object?>{'type':'string'},'uniqueItems':true}"));
      expect(
          schema,
          contains("'all':<String,Object?>{'type':'array',"
              "'items':<String,Object?>{'type':'integer','format':'int64'}}"));
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

  group('DOC-06 400 responses and form bodies', () {
    test('a route that binds input documents a 400', () {
      final op = _operation(code, '/search');
      expect(op, contains("'400':ResponseSpec("));
      expect(op, contains('errorEnvelopeSchema'));
    });

    test('a route without inputs has no 400', () {
      expect(_operation(code, '/open'), isNot(contains("'400'")));
    });

    test("a route's own 400 is kept, not duplicated", () {
      final op = _operation(code, '/item/<id>');
      expect("'400'".allMatches(op), hasLength(1));
      expect(op, contains("'Badid'"));
    });

    test('a form takes JSON or a form post', () {
      final op = _operation(code, '/login');
      expect(op, contains("'application/json':MediaType("));
      expect(op, contains("'application/x-www-form-urlencoded':MediaType("));
      expect(op, contains("'400':ResponseSpec("));
    });

    test('a form with a file is multipart only', () {
      final op = _operation(code, '/avatar');
      final body =
          op.substring(op.indexOf('requestBody:'), op.indexOf('responses:'));
      expect(body, contains("'multipart/form-data':MediaType("));
      expect(body, isNot(contains("'application/json'")));
    });
  });

  group('FW-16 trailing slash', () {
    test("@Get('/') is also served without the slash", () {
      expect(code, contains("'\$prefix/x/';"));
      expect(
          code,
          contains(
              'router.get(basePath.substring(0,basePath.length-1),__route);'));
    });

    test('other paths get no alias', () {
      final at = code.indexOf("'\$prefix/x/users';");
      final next = code.indexOf('spec.putOperation(', at);
      expect(code.substring(at, next), isNot(contains('substring(0,')));
    });
  });

  test('a look-alike annotation from another package is ignored (FW-15)',
      () async {
    final rw = TestReaderWriter(rootPackage: 'my_app');
    await rw.testing.loadIsolateSources();
    String? generated;
    await testBuilder(
      controllerBuilder(BuilderOptions.empty),
      {
        // Its URI contains "gisila", which used to be enough.
        'my_app|lib/gisila_fake.dart': 'class Public { const Public(); }',
        'my_app|lib/sample.dart': r'''
import 'package:gisila_doc/gisila_doc.dart' hide Public;
import 'gisila_fake.dart' as fake;

part 'sample.g.dart';

@Controller('/x')
@RequireAuth()
class FakeController {
  @Get('/secret')
  @fake.Public()
  Future<Map<String, Object?>> secret() async => <String, Object?>{};
}
''',
      },
      rootPackage: 'my_app',
      readerWriter: rw,
      outputs: {
        'my_app|lib/sample.gisila_doc.g.part':
            decodedMatches(predicate<String>((s) {
          generated = s;
          return true;
        })),
      },
    );
    final squashed = _squash(generated!);
    expect(squashed, contains('requireAuth:true'));
    expect(squashed, isNot(contains('isPublic:true')));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
