/// Arquivo: build_scanner.dart
/// Módulo: pillar_web_sw / varredura
/// Descrição: Walks build/web and builds the entry table in the format of
///   Flutter's precache_manifest.json, reading the disk (not the flag).
/// Dependências: package:crypto, package:path.
/// Premissas: exclusions mirror the SDK (content_hash.dart) plus *.br, *.gz
///   and the two files this package generates.
/// Edge Cases: symlinks are not followed; the walk order is irrelevant
///   because the result is sorted by url.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'manifest_entry.dart';

/// Files this package writes itself; never part of the table.
const generatedFiles = {'app-service-worker.js', 'app-sw-register.js'};

const _excludedNames = {
  'precache_manifest.json',
  'flutter_service_worker.js',
  ...generatedFiles,
};

const _excludedSuffixes = ['.map', '.symbols', '.info.json', '.br', '.gz'];

final _hashedName = RegExp(r'\.[0-9a-f]{8}\.[^./]+$');

/// SDK rule: the file name has `.<8 hex>.` before the extension.
bool isUrlHashed(String url) => _hashedName.hasMatch(url.split('/').last);

/// Whether [url] (relative, '/' separated) stays out of the table.
bool isExcluded(String url) {
  final segments = url.split('/');
  if (segments.any((s) => s.startsWith('.'))) return true;
  if (segments.first == 'canvaskit') return true;
  if (_excludedNames.contains(url)) return true;
  return _excludedSuffixes.any(url.endsWith);
}

/// First 8 hex chars of the SHA-256 of [bytes].
String shortHash(List<int> bytes) =>
    sha256.convert(bytes).toString().substring(0, 8);

/// Scans [buildDir]; the result is sorted by url.
List<ManifestEntry> scanBuild(Directory buildDir) {
  final entries = <ManifestEntry>[];
  for (final file in buildDir.listSync(recursive: true, followLinks: false)) {
    if (file is! File) continue;
    final url = p.posix.joinAll(
      p.split(p.relative(file.path, from: buildDir.path)),
    );
    if (isExcluded(url)) continue;
    final bytes = file.readAsBytesSync();
    entries.add(
      ManifestEntry(
        url: url,
        hash: shortHash(bytes),
        size: bytes.length,
        urlHashed: isUrlHashed(url),
      ),
    );
  }
  entries.sort((a, b) => a.url.compareTo(b.url));
  return entries;
}
