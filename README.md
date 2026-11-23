# pillar_web_sw

Pacote Dart que gera o service worker por release dos builds web Flutter. Desenho: ADR 0027 no repositório de documentação do Symmetris.

Estado: gerador (varredura, conferência, `release_id`, classificação), modelo do worker em JS, script de registro e interruptor de emergência.

## Uso

```bash
dart run pillar_web_sw:generate <build/web> [--config web_sw.yaml] [--release-id <id>] [--check-only] [--print-table] [--kill-switch]
```

- Varre o disco e monta a tabela no formato do `precache_manifest.json` (`url`, `hash` de 8 hex do SHA-256, `size`, `urlHashed`). Ficam de fora `*.map`, `*.symbols`, `*.info.json`, `*.br`, `*.gz`, arquivos de ponto, `precache_manifest.json`, `flutter_service_worker.js`, `canvaskit/**` e os dois arquivos gerados.
- Se `precache_manifest.json` existe, confere as entradas `urlHashed`; divergência nomeia o arquivo e sai com 1. Sem o manifesto não há erro.
- `release_id` = 8 hex do SHA-256 das linhas `url:hash` ordenadas do núcleo; `--release-id` substitui.
- `--check-only` só confere o manifesto; `--print-table` imprime a tabela (núcleo, sob demanda, ignorados) em JSON estável.
- Sem `--check-only`/`--print-table`, grava em `<build/web>` os arquivos `app-service-worker.js` (tabela e `release_id` embutidos; mesma entrada, mesmos bytes) e `app-sw-register.js`. Rode depois do último passo que mexe no build.
- `--kill-switch` grava, no mesmo nome `app-service-worker.js`, um worker que apaga os caches `<cachePrefix>-*` e se desregistra (não varre o build; não combina com `--check-only`/`--print-table`). Publique-o para recolher uma release ruim; depois rode o gerador normal.
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

## Worker e registro

O modelo do worker é uma constante Dart (`lib/src/templates/`), não um arquivo de asset: assim funciona igual em `dart run`, `dart pub global` e executável compilado. Node não é dependência (só serve para os testes JS, opcionais).

Estratégias (ADR 0027, item 6): navegação rede primeiro com 3 s de limite e, sem rede, o `index.html` da release; núcleo sem hash e `urlHashed` do cache da release primeiro; sob demanda guardado no primeiro uso em `<prefix>-ondemand`; `config.js` rede primeiro com cache de reserva (fica fora do núcleo e da conferência de hash, pois muda por tenant); fontes e CanvasKit do CDN (`fonts.gstatic.com`, `www.gstatic.com/flutter-canvaskit/`) com `stale-while-revalidate` em `<prefix>-runtime` (só resposta CORS, até 60 entradas). Não intercepta: não-GET, `Range`, outras origens, `neverIntercept` e arquivo ausente em `assets/`, `canvaskit/`, `icons/` ou `main.dart*` (vai ao servidor e recebe o 404 real). Instalação com `cache: 'reload'`, status 200 e hash conferido; qualquer falha rejeita a instalação e o worker anterior segue. Sem `skipWaiting` automático.

Mensagens (todas com prefixo `app-sw-`): `{type: 'app-sw-skip-waiting'}` assume o controle; `{type: 'app-sw-status'}` responde `{releaseId, state, lastInstallError}` (pela porta enviada em `ports[0]` ou pelo `event.source`).

Registro no `index.html`, depois do `flutter_bootstrap.js` ou antes dele, tanto faz:

```html
<script src="app-sw-register.js" defer></script>
```

Registra no evento `load`, escopo da pasta do script, `updateViaCache: 'none'`; nunca lança. A única superfície é o evento `app-sw-update-available` na `window` (`detail.registration`), disparado quando há release nova esperando atrás de uma aberta. Texto e lugar do aviso são do app; para aplicar: `registration.waiting.postMessage({type: 'app-sw-skip-waiting'})` e recarregar em `controllerchange`.

## Testes

`dart test` roda tudo. Os testes do comportamento do worker (`test/worker_js_test.dart`) usam o Node do PATH com mocks de `caches`/`fetch`/`self` (`test/js/`); sem Node eles são pulados com a mensagem "JS NÃO EXECUTADO" e ficam só os testes Dart sobre o texto gerado.
