/// Arquivo: manifest_entry.dart
/// Módulo: pillar_web_sw / modelo
/// Descrição: One file of the web build, in the same shape as an entry of
///   Flutter's precache_manifest.json.
/// Dependências: nenhuma.
/// Premissas: `url` is relative to build/web, with '/' separators and no
///   leading slash; `hash` is the first 8 hex chars of the SHA-256.
/// Edge Cases: none.
library;

/// A file found in the build output.
class ManifestEntry {
  const ManifestEntry({
    required this.url,
    required this.hash,
    required this.size,
    required this.urlHashed,
  });

  final String url;
  final String hash;
  final int size;

  /// True when the file name carries the hash (`name.<8 hex>.ext`).
  final bool urlHashed;

  Map<String, Object> toJson() => {
    'url': url,
    'hash': hash,
    'size': size,
    'urlHashed': urlHashed,
  };
}
