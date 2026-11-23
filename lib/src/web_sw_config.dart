/// Arquivo: web_sw_config.dart
/// Módulo: pillar_web_sw / configuração
/// Descrição: Per-app configuration read from web_sw.yaml.
/// Dependências: package:yaml.
/// Premissas: globs use POSIX paths relative to build/web; every key is
///   optional and falls back to a default that caches the whole build.
/// Edge Cases: wrong types or unknown keys raise [ConfigException] so a typo
///   does not silently change what is cached.
library;

import 'package:yaml/yaml.dart';

class ConfigException implements Exception {
  ConfigException(this.message);
  final String message;
  @override
  String toString() => message;
}

class WebSwConfig {
  const WebSwConfig({
    this.cachePrefix = 'app',
    this.core = const ['**'],
    this.onDemand = const [],
    this.ignore = const [],
    this.neverIntercept = const [],
    this.noHashCheck = const [],
    this.navigationFallback = true,
  });

  final String cachePrefix;
  final List<String> core;
  final List<String> onDemand;
  final List<String> ignore;
  final List<String> neverIntercept;

  /// Globs of core entries checked by status only at install (no hash).
  final List<String> noHashCheck;
  final bool navigationFallback;

  static const _keys = {
    'cachePrefix',
    'core',
    'onDemand',
    'ignore',
    'neverIntercept',
    'noHashCheck',
    'navigationFallback',
  };

  factory WebSwConfig.parse(String source) {
    final Object? doc;
    try {
      doc = loadYaml(source);
    } on YamlException catch (e) {
      throw ConfigException('web_sw.yaml inválido: ${e.message}');
    }
    if (doc == null) return const WebSwConfig();
    if (doc is! YamlMap) {
      throw ConfigException('web_sw.yaml deve ser um mapa de chaves');
    }
    final unknown = doc.keys.where((k) => !_keys.contains(k));
    if (unknown.isNotEmpty) {
      throw ConfigException('chave desconhecida em web_sw.yaml: $unknown');
    }
    const d = WebSwConfig();
    return WebSwConfig(
      cachePrefix: _string(doc, 'cachePrefix') ?? d.cachePrefix,
      core: _strings(doc, 'core') ?? d.core,
      onDemand: _strings(doc, 'onDemand') ?? d.onDemand,
      ignore: _strings(doc, 'ignore') ?? d.ignore,
      neverIntercept: _strings(doc, 'neverIntercept') ?? d.neverIntercept,
      noHashCheck: _strings(doc, 'noHashCheck') ?? d.noHashCheck,
      navigationFallback:
          _bool(doc, 'navigationFallback') ?? d.navigationFallback,
    );
  }

  static String? _string(YamlMap doc, String key) {
    final v = doc[key];
    if (v == null) return null;
    if (v is! String || !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(v)) {
      throw ConfigException('$key deve ser um texto sem espaços ou "/"');
    }
    return v;
  }

  static List<String>? _strings(YamlMap doc, String key) {
    final v = doc[key];
    if (v == null) return null;
    if (v is! YamlList || v.any((e) => e is! String)) {
      throw ConfigException('$key deve ser uma lista de textos');
    }
    return List<String>.unmodifiable(v.cast<String>());
  }

  static bool? _bool(YamlMap doc, String key) {
    final v = doc[key];
    if (v == null) return null;
    if (v is! bool) throw ConfigException('$key deve ser true ou false');
    return v;
  }
}
