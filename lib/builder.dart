/// build_runner entrypoint for the gisila_doc generator.
///
/// This file is referenced from `build.yaml`'s `import:` field; users
/// never import it directly.
library gisila_doc.builder;

import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/builder/controller_generator.dart';

/// Factory referenced by `build.yaml`.
Builder controllerBuilder(BuilderOptions _) =>
    SharedPartBuilder(const [ControllerGenerator()], 'gisila_doc');
