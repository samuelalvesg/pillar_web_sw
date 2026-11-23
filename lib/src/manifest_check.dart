/// Arquivo: manifest_check.dart
/// Módulo: pillar_web_sw / conferência
/// Descrição: Cross-checks the disk scan against Flutter's
///   precache_manifest.json when the build has one.
/// Dependências: dart:convert, dart:io.
/// Premissas: only entries with `urlHashed: true` are checked, because only
///   those hashes are tied to the file name.
/// Edge Cases: absent manifest is not an error; a malformed one is reported
///   as a divergence so the build does not ship on a broken input.
library;

import 'dart:convert';
import 'dart:io';

import 'manifest_entry.dart';

/// Returns one message per divergence (empty when consistent).
List<String> checkAgainstManifest(
  Directory buildDir,
  List<ManifestEntry> scanned,
) {
  final file = File('${buildDir.path}/precache_manifest.json');
  if (!file.existsSync()) return const [];

  final List<dynamic> listed;
  try {
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    listed = json['entries'] as List<dynamic>;
  } on Object catch (e) {
    return ['precache_manifest.json inválido: $e'];
  }

  final byUrl = {for (final e in scanned) e.url: e};
  final problems = <String>[];
  for (final raw in listed) {
    final entry = raw as Map<String, dynamic>;
    if (entry['urlHashed'] != true) continue;
    final url = (entry['url'] as String).replaceFirst(RegExp(r'^/+'), '');
    final onDisk = byUrl[url];
    if (onDisk == null) {
      problems.add('$url: listado no manifesto e ausente no disco');
    } else if (onDisk.hash != entry['hash']) {
      problems.add(
        '$url: hash do manifesto ${entry['hash']} difere do disco '
        '${onDisk.hash}',
      );
    }
  }
  return problems;
}
