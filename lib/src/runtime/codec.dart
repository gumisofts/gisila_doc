/// Re-exports the codec helpers from the `gisila` core package so that
/// generated controller code (`*.g.dart`) can import a single package
/// and still get `jsonResponse`, `emptyResponse`, `readJsonBody`,
/// `coerce`, and `BadRequestException`.
///
/// All runtime request/response utilities live in `gisila`; this file
/// exists solely to keep the `gisila_doc` public surface unchanged.
library gisila_doc.runtime.codec;

export 'package:gisila/gisila.dart'
    show BadRequestException, coerce, emptyResponse, jsonResponse, readJsonBody;
