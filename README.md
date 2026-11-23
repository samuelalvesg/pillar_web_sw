# pillar_web_sw

Pacote Dart que gera o service worker por release dos builds web Flutter. Desenho: ADR 0027 no repositório de documentação do Symmetris.

Estado: só o **gerador** (varredura, conferência, `release_id`, classificação). O worker em JS e o registro ainda não são gravados.

## Uso

```bash
dart run pillar_web_sw:generate <build/web> [--config web_sw.yaml] [--release-id <id>] [--check-only] [--print-table]
```

- Varre o disco e monta a tabela no formato do `precache_manifest.json` (`url`, `hash` de 8 hex do SHA-256, `size`, `urlHashed`). Ficam de fora `*.map`, `*.symbols`, `*.info.json`, `*.br`, `*.gz`, arquivos de ponto, `precache_manifest.json`, `flutter_service_worker.js`, `canvaskit/**` e os dois arquivos gerados.
- Se `precache_manifest.json` existe, confere as entradas `urlHashed`; divergência nomeia o arquivo e sai com 1. Sem o manifesto não há erro.
- `release_id` = 8 hex do SHA-256 das linhas `url:hash` ordenadas do núcleo; `--release-id` substitui.
- `--check-only` só confere o manifesto; `--print-table` imprime a tabela (núcleo, sob demanda, ignorados) em JSON estável.
- Códigos de saída: 0 ok, 1 manifesto diverge do disco, 2 erro de uso (argumentos, diretório ou configuração inválidos).

## `web_sw.yaml`

Todas as chaves são opcionais; sem o arquivo, tudo vai para o núcleo. Procura `./web_sw.yaml` quando `--config` não é informado.

```yaml
cachePrefix: bible          # prefixo dos caches
core: ["**"]                # globs do núcleo (pré-cache da release)
onDemand: ["assets/bible/**"]  # guardados no primeiro uso
ignore: ["**/*.txt"]        # nunca em cache
neverIntercept: [/api/, /auth/]  # prefixos que o worker não toca
navigationFallback: true    # index.html da release para navegação offline
```

Precedência: `ignore` > `onDemand` > `core`; arquivo que não casa com nenhuma lista é ignorado.
