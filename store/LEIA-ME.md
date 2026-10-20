# Publicação do Bee Bee na Google Play — roteiro

Tudo o que dá para preparar fora do Play Console já está nesta pasta e no projeto. Este roteiro
lista, em ordem, o que só você pode fazer (contas, IDs e declarações) e onde colar cada coisa.

## O que já está pronto

| Item | Onde |
|---|---|
| Bundle assinado para envio (`.aab`) | `build/android/beebee-release.aab`, gerado por `bash tools/build_release.sh` |
| Chave de assinatura e senha | `..\Bee Bee - chaves\` (fora do git) — **faça backup dessa pasta** |
| Capturas de tela (7 por idioma, 1080x2160) | `store/screenshots/pt-BR/` e `store/screenshots/en-US/` |
| Imagem de destaque (1024x500) | `store/feature_graphic.png` |
| Ícone da loja (512x512) | `store/icon_512.png` (o desenho do ícone do app, sem alteração) |
| Nome e descrições (pt-BR e en-US) | `store/listing.md` |
| Política de privacidade (pt-BR e en) | `store/privacy_policy.md` |

Para refazer as imagens depois de mudar o jogo:
`godot --path . --audio-driver Dummy --script tools/godot/render_store_shots.gd -- --lang=pt`
(e de novo com `--lang=en`), depois `python tools/make_feature_graphic.py` e, para o site,
`python tools/make_site_assets.py`.

## 1. Conta e app no Play Console

1. Crie a conta de desenvolvedor em https://play.google.com/console (taxa única de US$ 25).
   Contas pessoais novas precisam passar por um **teste fechado** antes de liberar a produção
   (até onde sei, 12 testadores por 14 dias; o Play Console mostra a regra atual).
2. Crie o app: nome "Bee Bee", idioma padrão pt-BR, tipo **Jogo**, **Gratuito**.
3. O nome do pacote é `com.beebeegame.beebee`. Ele não pode ser trocado depois do primeiro envio.

## 2. Anúncios (AdMob)

O jogo está com os **IDs de teste do Google**: mostram anúncios de teste e não pagam nada.

1. Crie a conta em https://admob.google.com e adicione o app (Android).
2. Crie um bloco de anúncios do tipo **Intersticial**.
3. Troque os dois IDs:
   - **ID do app** (formato `ca-app-pub-XXXX~YYYY`): em `project.godot`, adicione na seção
     `[admob]` a linha `general/android/app_id="ca-app-pub-XXXX~YYYY"` (ou, no editor,
     *Projeto > Configurações do Projeto > AdMob > General > Android > App Id*).
   - **ID do bloco** (formato `ca-app-pub-XXXX/ZZZZ`): constante `INTERSTITIAL_ID` em
     `scripts/ads.gd`.
4. No AdMob, em *Privacidade e mensagens*, crie a mensagem de consentimento para os
   **regulamentos europeus** (GDPR). Sem ela o formulário de consentimento não aparece na
   Europa e os anúncios lá ficam limitados.
5. Nunca toque em anúncios reais no seu próprio aparelho: isso pode suspender a conta. Para
   testar com os IDs reais, cadastre o aparelho como dispositivo de teste no AdMob.
6. O AdMob pede um arquivo **app-ads.txt** no site de desenvolvedor informado na ficha da
   Play (por exemplo `https://beebee.cyberhat.com.br/app-ads.txt`), com a linha que ele mostra
   em *Apps > app-ads.txt* (`google.com, pub-XXXX, DIRECT, f08c47fec0942fa0`). Sem ele o app
   fica sem verificação e pode receber menos anúncios. Coloque o arquivo em `site/` antes de
   rodar `tools/build_site.sh`.

Como os anúncios funcionam no jogo: um intersticial ao tocar em "Play Again", no máximo a cada
6 partidas e nunca com menos de 3 minutos do anterior nem nos 3 primeiros minutos de jogo. Os números estão no topo de
`scripts/ads.gd` (`RUNS_BETWEEN_ADS`, `MIN_SECONDS_BETWEEN_ADS`).

## 3. Placar online (opcional)

Está pronto, mas **desligado**. Usa o Google Play Games: quem hospeda as pontuações é o Google,
sem banco de dados nosso. Os quatro passos para ligar estão no topo de
`scripts/leaderboard.gd`. Você vai precisar das impressões digitais SHA-1:

- da **chave de envio**: está em `..\Bee Bee - chaves\impressoes-digitais.txt`;
- da **chave de assinatura do app** que o Google cria: Play Console > *Integridade do app*.

## 4. Ficha da loja

Cole os textos de `store/listing.md`, envie as capturas, a imagem de destaque e o ícone
`store/icon_512.png`.

## 5. Política de privacidade

O Play Console exige um endereço público. O site do jogo já leva a página pronta:
**https://beebee.cyberhat.com.br/privacidade.html** (o `tools/build_site.sh` a gera a partir de
`store/privacy_policy.md`, em português e inglês). Antes de publicar o site, preencha os dois
campos entre colchetes nesse `.md` (`[NOME DO DESENVOLVEDOR]` e `[E-MAIL DE CONTATO]`); o
script avisa se ainda estiverem lá.

## 6. Licenças da música e dos sons

O jogo tem anúncios, então é uso comercial. A música foi feita no **Suno** e os efeitos
sonoros no **ElevenLabs**: nos dois, só o que foi gerado com um **plano pago** pode ser usado
comercialmente (pelo que sei dos termos; confira nos sites). Se algo foi gerado no plano
gratuito, gere de novo num plano pago antes de publicar.

## 7. Declarações do Play Console (Conteúdo do app)

Sugestões de resposta, de acordo com o que o jogo faz hoje. Confira cada uma na hora: as
perguntas mudam, e a responsabilidade pela declaração é sua.

- **Anúncios:** Sim, o app contém anúncios.
- **Acesso ao app:** todas as funções estão disponíveis sem login.
- **Classificação de conteúdo** (questionário IARC): jogo sem violência, sem linguagem
  imprópria, sem compras e sem interação entre usuários. O resultado esperado é **Livre**.
- **Público-alvo:** recomendo **13 anos ou mais**. Marcar faixas abaixo de 13 coloca o jogo no
  programa *Famílias*, que exige anúncios certificados para crianças e outras regras; o jogo
  não está configurado para isso.
- **Segurança dos dados:** o jogo em si não coleta nada, mas o SDK de anúncios do Google sim.
  Declare como **coletados e compartilhados** (finalidade: publicidade, análise e prevenção de
  fraude), todos **criptografados em trânsito**:
  - Localização aproximada
  - Identificadores do dispositivo ou outros IDs
  - Interações com o app
  - Diagnóstico (registros de falhas e desempenho)

  A lista oficial do Google para o SDK de anúncios está em
  https://developers.google.com/admob/android/privacy/play-data-disclosure — confira por ela.
- **ID de publicidade:** Sim, o app usa (o SDK de anúncios declara a permissão `AD_ID`).

## 8. Envio

1. `bash tools/build_release.sh` gera `build/android/beebee-release.aab`.
2. `python tools/check_android_build.py` confere o que foi gerado: bibliotecas alinhadas para
   páginas de memória de 16 KB (o Play recusa apps novos sem isso), app declarado como **jogo**,
   backup do Android permitido, nome do pacote e versão. Tem de terminar em "all good".
3. A cada envio novo, aumente `version/code` em 1 no preset "Android Release" de
   `export_presets.cfg` (o Play recusa um código repetido).
4. Envie primeiro para **Teste interno**, instale pelo link de teste e jogue: é a única forma
   de conferir anúncios e placar exatamente como o usuário final vai ver.

O `export_presets.cfg` está no git (desde 14/10): se o editor do Godot o regravar, o `git diff`
mostra o que mudou. Confira nos dois presets Android: `package/app_category=2` (Game), `user_data_backup/allow=true`,
`permissions/vibrate=true`; e no preset "Android", `gradle_build/compress_native_libraries=true`.

## Requisitos do aparelho

Android 10 ou mais novo (é o mínimo que o build declara), ARM de 32 ou 64 bits. Download estimado por
aparelho: cerca de 40 MB.
