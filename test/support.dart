/// Arquivo: support.dart
/// Módulo: pillar_web_sw / testes
/// Descrição: Helpers to build fixture build/web folders in temp dirs.
/// Dependências: dart:io, package:test.
/// Premissas: each test gets its own directory, removed on tear down.
/// Edge Cases: none.
library;

import 'dart:convert';
import 'dart:io';

import 'package:pillar_web_sw/pillar_web_sw.dart';
import 'package:test/test.dart';

/// Writes [files] (url -> text) into a fresh temp dir removed after the test.
Directory fixture(Map<String, String> files) {
  final dir = Directory.systemTemp.createTempSync('pws_');
  addTearDown(() => dir.deleteSync(recursive: true));
  files.forEach((url, text) {
    File('${dir.path}/$url')
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
  });
  return dir;
}

/// Files of a typical Flutter web build (no content hash).
Map<String, String> baseBuild() => {
  'index.html': '<html></html>',
  'flutter.js': 'flutter',
  'flutter_bootstrap.js': 'boot',
  'main.dart.js': 'main',
  'main.dart.js.map': 'map',
  'main.dart.js.symbols': 'sym',
  'manifest.json': '{}',
  'version.json': '{}',
  'flutter_service_worker.js': 'stub',
  '.last_build_id': 'x',
  'assets/AssetManifest.bin': 'bin',
  'assets/bible/nvi.2a2a2a2a.json': 'big',
  'main.dart.wasm.br': 'br',
  'main.dart.wasm.gz': 'gz',
  'app-service-worker.js': 'old',
  'app-sw-register.js': 'old',
};

/// Extra files of a build made with --no-web-resources-cdn (local CanvasKit).
Map<String, String> localCanvaskitFiles() => {
  'canvaskit/canvaskit.js': 'ckjs',
  'canvaskit/canvaskit.wasm': 'ckwasm',
  'canvaskit/canvaskit.js.symbols': 'sym',
  'canvaskit/skwasm.js': 'skjs',
  'canvaskit/skwasm.wasm': 'skwasm',
  'canvaskit/skwasm_heavy.wasm': 'heavy',
  'canvaskit/chromium/canvaskit.wasm': 'chromium',
};

/// Writes a precache_manifest.json into [dir] listing [entries].
void writeManifest(Directory dir, List<Map<String, Object>> entries) {
  File(
    '${dir.path}/precache_manifest.json',
  ).writeAsStringSync(jsonEncode({'version': 1, 'entries': entries}));
}

/// Runs the CLI in-process; returns (code, stdout, stderr).
(int, String, String) cli(List<String> args) {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = runGenerate(args, out: out, err: err);
  return (code, out.toString(), err.toString());
}
