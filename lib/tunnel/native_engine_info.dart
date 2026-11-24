import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../app_info/app_info.dart';

DynamicLibrary _openLibrary() => DynamicLibrary.open('libdirka_engine.so');

String _readText(DynamicLibrary library, String symbol) => library
    .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
      symbol,
    )()
    .toDartString();

typedef EngineLicense = ({List<String> packages, String text});

abstract final class NativeEngineInfo {
  static Future<EngineInfo> loadInfo() => Isolate.run(() {
    final library = _openLibrary();
    final info = jsonDecode(
      _readText(library, 'dirka_engine_metadata'),
    ) as Map<String, Object?>;
    return (
      engineVersion: info['engineVersion'] as String,
      protocolVersion: info['protocolVersion'] as int,
      upstreamRevision: info['upstreamRevision'] as String,
      upstreamLicense: _readText(library, 'dirka_engine_upstream_license'),
    );
  });

  static Future<List<EngineLicense>> loadDependencyLicenses() =>
      Isolate.run(() {
        final json = _readText(
          _openLibrary(),
          'dirka_engine_dependency_licenses',
        );
        final entries = (jsonDecode(json) as List).cast<Map<String, Object?>>();
        return [
          for (final entry in entries)
            (
              packages: (entry['packages'] as List).cast<String>(),
              text: entry['text'] as String,
            ),
        ];
      });
}
