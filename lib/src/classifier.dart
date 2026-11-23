/// Arquivo: classifier.dart
/// Módulo: pillar_web_sw / classificação
/// Descrição: Splits the scanned entries into core / on-demand / ignored
///   (ADR 0027 item 6), computes the release id and builds the table the
///   worker template embeds.
/// Dependências: package:glob, package:crypto.
/// Premissas: precedence is ignore > onDemand > core; an entry matching no
///   list is ignored. release_id covers the core only, so on-demand content
///   never forces a new release.
/// Edge Cases: the JSON uses fixed key order and url-sorted lists, so equal
///   input gives byte-identical output.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:glob/glob.dart';

import 'manifest_entry.dart';
import 'web_sw_config.dart';

/// How the worker serves a core entry.
const strategyHashed = 'cache-first';
const strategyRelease = 'release-cache-first';
const strategyOnDemand = 'on-demand';

/// Install-time integrity check of a core entry.
const checkHash = 'hash';
const checkStatus = 'status';

// Proxies such as Cloudflare rewrite these on the edge (link injection,
// e-mail obfuscation, minification), so no content hash can match.
const _rewritableExtensions = {
  'html', 'htm', 'svg', 'xml', 'txt', 'css', 'json', //
};

/// `status` for rewritable text types or entries matching [noHashCheck],
/// `hash` for code and binaries.
String checkFor(String url, List<Glob> noHashCheck) {
  final name = url.split('/').last;
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  if (_rewritableExtensions.contains(ext)) return checkStatus;
  return _matchesAny(noHashCheck, url) ? checkStatus : checkHash;
}

class Classification {
  const Classification({
    required this.core,
    required this.onDemand,
    required this.ignored,
  });

  final List<ManifestEntry> core;
  final List<ManifestEntry> onDemand;
  final List<ManifestEntry> ignored;
}

bool _matchesAny(List<Glob> globs, String url) =>
    globs.any((g) => g.matches(url));

List<Glob> _compile(List<String> patterns) => [
  for (final p in patterns) Glob(p, recursive: true),
];

/// [entries] must already be sorted by url; order is preserved.
Classification classify(List<ManifestEntry> entries, WebSwConfig config) {
  final ignore = _compile(config.ignore);
  final onDemand = _compile(config.onDemand);
  final core = _compile(config.core);
  final result = (
    core: <ManifestEntry>[],
    od: <ManifestEntry>[],
    ig: <ManifestEntry>[],
  );
  for (final e in entries) {
    if (_matchesAny(ignore, e.url)) {
      result.ig.add(e);
    } else if (_matchesAny(onDemand, e.url)) {
      result.od.add(e);
    } else if (_matchesAny(core, e.url)) {
      result.core.add(e);
    } else {
      result.ig.add(e);
    }
  }
  return Classification(
    core: result.core,
    onDemand: result.od,
    ignored: result.ig,
  );
}

/// First 8 hex of the SHA-256 over the sorted `url:hash` lines of the core,
/// plus [model] (the worker template version) when given, so two different
/// workers never share a release cache name.
String computeReleaseId(List<ManifestEntry> core, {String model = ''}) {
  final sorted = [...core]..sort((a, b) => a.url.compareTo(b.url));
  final lines = sorted.map((e) => '${e.url}:${e.hash}').join('\n');
  final text = model.isEmpty ? lines : '$lines\nmodel:$model';
  return sha256.convert(utf8.encode(text)).toString().substring(0, 8);
}

/// The deterministic data structure the worker template embeds.
Map<String, Object> buildTable({
  required Classification classification,
  required WebSwConfig config,
  required String releaseId,
}) {
  final noHash = _compile(config.noHashCheck);
  Map<String, Object> coreJson(ManifestEntry e) => {
    ...e.toJson(),
    'strategy': e.urlHashed ? strategyHashed : strategyRelease,
    'check': checkFor(e.url, noHash),
  };
  Map<String, Object> onDemandJson(ManifestEntry e) => {
    ...e.toJson(),
    'strategy': strategyOnDemand,
  };
  return {
    'cachePrefix': config.cachePrefix,
    'releaseId': releaseId,
    'navigationFallback': config.navigationFallback,
    'neverIntercept': [...config.neverIntercept]..sort(),
    'core': classification.core.map(coreJson).toList(),
    'onDemand': classification.onDemand.map(onDemandJson).toList(),
    'ignored': classification.ignored.map((e) => e.url).toList(),
  };
}

/// Stable, pretty JSON of [table].
String encodeTable(Map<String, Object> table) =>
    const JsonEncoder.withIndent('  ').convert(table);
