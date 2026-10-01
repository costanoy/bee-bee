# Bee Bee — contexto do projeto (handoff para um novo chat)

Jogo mobile (Android) feito em **Godot 4.7.1**, por um dev solo brasileiro (falar em **pt-BR**).
Endless climber vertical: a abelha sobe tocando à esquerda/direita, passa pelos buracos das
roseiras e precisa pegar **todas** as flores (perder uma = game over).

## Regras de trabalho (preferências do usuário)
- **Commit + push automático** de toda mudança verificada em `costanoy/bee-bee` (branch `main`), sem perguntar. Mensagens de commit em inglês, explicando o porquê. Terminar com `Co-Authored-By: Claude ... <noreply@anthropic.com>`.
- Depois de mudanças visíveis: **gerar APK e servir na rede local** para o usuário testar no celular (ver "Build").
- Antes de dizer que algo funciona: **testar** (boot headless + screenshots reais via SubViewport).
- **Conversão para voxel art: um asset por vez.** Para cada asset: construir → renderizar prévias (imagens/GIF + captura dentro do jogo) → **mostrar e esperar o usuário pedir ajustes/aprovar** → só então ligar no jogo.
- Testes de gameplay ficam marcados com `TEST` no código, com o valor antigo anotado para poder reverter.

## Caminhos e ferramentas
- Projeto: `C:\Users\Vinicius Costa\Desktop\Jogos\Bee Bee`
- Godot: `C:\Users\Vinicius Costa\Desktop\Apps\Godot_v4.7.1-stable_win64.exe`
- Blender 5.2: `C:\Program Files\Blender Foundation\Blender 5.2\blender.exe` (rodar `--background --factory-startup --python <script> -- <args>`; às vezes dá `EXCEPTION_ACCESS_VIOLATION` **ao fechar**, depois de salvar — é inofensivo). EEVEE funciona em background.
- Python do Windows (tem Pillow e numpy). No Git Bash, passar caminhos estilo `C:/...` para o python.

## Build e teste no celular
- Boot check: `"<godot>" --headless --path . --quit-after 5`
- Reimportar assets: `"<godot>" --headless --path . --import`
- APK (precisa de temp curto + sandbox desligado):
  `TEMP="C:\jtmp" TMP="C:\jtmp" "<godot>" --headless --path . --export-debug "Android" build/android/beebee-debug.apk`
- Servir: `npx serve -l tcp://0.0.0.0:8090` dentro de `build/` (rodar em background). **Usar a porta 8090** — a 8080 é de outro projeto do usuário ("Duelel"), não mexer.
- O IP Wi-Fi muda (ver `ipconfig`). Link: `http://<ip>:8090/android/beebee-debug.apk` — conferir com `curl` (200) antes de mandar.
- Screenshots reais: script `extends SceneTree` que cria um `SubViewport` 1080x2160 com `size_2d_override = (400, 800)` + `size_2d_override_stretch = true`, instancia `res://scripts/main.gd` num `Node2D`, espera frames e salva `sv.get_texture().get_image()`. Rodar **sem** `--headless` e com `--audio-driver Dummy`. O jogo pode **pausar sozinho** quando a janela perde o foco: no loop de espera, forçar `paused = false`, `g.state = g.State.PLAYING`, `g.pause_screen.visible = false`.

## Arquitetura
- `scripts/main.gd` — toda a lógica (estado, câmera 2D, spawn de fileiras, colisão, score, UI). Tudo construído por código (a cena `main.tscn` é só a raiz). **A simulação é 2D** num plano de 400 px de largura.
- `scripts/view3d.gd` — **o visual do jogo é 3D em tempo real**: espelha o estado 2D a cada frame num cenário 3D (mesmo x/y no plano z=0, 1 unidade 3D = 40 px). Câmera em perspectiva inclinada 7°, céu procedural com dia→entardecer→noite, névoa de profundidade, sol que se põe, estrelas, partículas ao pegar flor. `USE_3D_VIEW` em `main.gd` (false volta ao 2D antigo). Sombras desligadas (custo no celular).
- Modelos 3D em `models/*.glb`. `view3d.gd`: dicionário `voxel` mapeia slot→arquivo voxel; `spawn()` liga `vertex_color_use_as_albedo` nos modelos voxel (o import glTF do Godot deixa desligado → ficam brancos). Roseira usa `hedge_models` + `hedge_seg_w`; flores usam `flower_scale`.
- `scripts/bee.gd`, `obstacle.gd`, `flower.gd`, `cloud.gd`, `seagull.gd`, `sky.gd` — lógica 2D (os sprites 2D ficam escondidos; `sky.gd` ainda dá o relógio dia/noite e os eventos lua/Júpiter/OVNI/abelha brilhosa).
- UI 2D por cima, **toda em blocos voxel desenhados por código** (sem imagens): fonte pixelada **Jersey 10** (OFL, `fonts/Jersey10-OFL.txt`) com contorno roxo-escuro `UI_INK`; `scripts/voxel_plate.gd` desenha os blocos (botões e painéis) numa grade de `UI_CELL = 3` px, com paletas `honey`/`green`/`dark`, e afunda a face ao ser tocado; `_make_block_button()` em `main.gd` monta os botões (verde = começar/continuar a partida, mel = o resto, escuro = ícones e cartões); `scripts/voxel_logo.gd` desenha o logo "Bee Bee" em cubos, com a abelha da skin atual flutuando entre as palavras; ícones (pause, play, nota, setas) são grades de pixels em `main.gd` — usar **tamanho de célula inteiro**, senão aparecem frestas. Game over mostra Score e Record lado a lado num painel, com o selo "NEW!" no canto.

## Conversão para voxel art (concluída: todos os modelos do jogo são voxel)
Pipeline: `tools/blender/voxel_kit.py` (grade compartilhada `VOX = 0.04` = 1,6 px por cubo no jogo; cores em sRGB direto na camada de cor do bmesh — **não** converter para linear; só faces expostas; `vk.export`; `vk.Preview` para renders de revisão).

| Asset | Script | Status |
|---|---|---|
| Abelha | `make_voxel_bee.py <models> <preview> [skin] [export_only]` → `bee_voxel.glb` (normal) e `bee_voxel_<skin>.glb`; **na grade do mundo (0,04) e já no tamanho do jogo**, desenhada sem escala (`BEE_SCALE 1.0`) | ✅ no jogo (sem patinhas, antena contínua; `LiveEyes`/`DeadEyes`, `WingPivotL/R`). Skins = mesma abelha com outra paleta (`SKINS` no script): `rosy`, `mint`, `ice`, `grape`, `queen` (com coroa) e `shining` |
| Roseira | `make_voxel_hedge.py` → `hedge_voxel_a/b/c.glb` (tiles de 24 cubos = 0.96 un., emendáveis) | ✅ no jogo (mais rosas + espinhos) |
| Flores | `make_voxel_flower.py` → `flower_voxel_red/yellow/blue.glb` (mesma forma, só muda a cor; usar escala 1.0) | ✅ no jogo (aprovadas como estavam; `FLOWER_SCALE 1.0`) |
| Nuvens | `make_voxel_cloud.py` → `cloud_voxel_a/b/c.glb` (grande/média/pequena = 45/35/25 cubos, translúcidas `ALPHA = 0.6`) | ✅ no jogo (`_build_cloud` em `view3d.gd` escolhe o modelo pela largura da nuvem 2D, escala 1.0, `depth_draw_mode ALWAYS` para as camadas internas não aparecerem como riscos) |
| Gaivota | `make_voxel_gull.py` → `gull_voxel.glb` (21 cubos de comprimento, asas em `WingPivotL/R` como a low poly; escala 1.0) | ✅ no jogo |
| Chão | `make_voxel_ground.py` → `ground_voxel.glb` (16 un. de largura, topo da grama em y=0; cor varia por retalho e as faces iguais são fundidas com `vk.build_mesh_merged`, ~4,6 mil polígonos) | ✅ no jogo |
| Árvores | `make_voxel_tree.py` → `tree_voxel_round_a/b/c.glb` e `tree_voxel_pine_a/b/c.glb` (a/b/c = grande/média/pequena, 58/49/41 cubos de altura; sem as faces de trás e de baixo, que a câmera nunca vê) | ✅ no jogo (sem escala nem giro aleatório; posição presa à grade) |
| Lua | `make_voxel_moon.py` → `moon_voxel.glb` (raio 25 cubos, crateras em volta toda porque o jogo gira a lua; faces fundidas, ~6,9 mil polígonos) | ✅ no jogo, **brilhante** (`_glowing()` em `view3d.gd` põe o material sem sombreamento; iluminada pela luz fraca da noite ela ficava cinza e com riscos pretos nos degraus do lado escuro) |
| Júpiter | `make_voxel_jupiter.py` → `jupiter_voxel.glb` (raio 31 cubos = 1,25 un., já no tamanho final; faixas em volta toda e a Grande Mancha; ~9,1 mil polígonos) | ✅ no jogo, brilhante como a lua, escala 1.0 |
| OVNI | `make_voxel_ufo.py` → `ufo_voxel.glb` (49 cubos de diâmetro, já no tamanho final; malhas `Hull`, `Alien` e `Dome` — cúpula translúcida; paleta escurecida com `glow()` porque sem sombreamento o jogo mostra a cor do vértice como luz linear, bem mais clara) | ✅ no jogo, brilhante, escala 1.0 |
| Fundo: montanhas | `make_voxel_backdrop_hills.py` → `backdrop_voxel_hills.glb` (três camadas — colinas verdes, colinas azuis, montanhas com neve — em **cubos de 0,2 un.**, 5× maiores, porque a 95 un. de distância a perspectiva os reduz ao tamanho dos outros cubos na tela; luz e sombra pintadas; ~4,2 mil polígonos) | ✅ no jogo |
| Fundo: cidade | `make_voxel_backdrop_city.py` → `backdrop_voxel_city.glb` (casas em tons pastel com telhados e janelas, colinas verdes atrás; mesmos cubos de 0,2 un.; as janelas são uma malha separada `Windows` com material emissivo; ~3,4 mil polígonos) | ✅ no jogo |
| Abelha prateada (skin do score 300; id interno `shining`) | `make_voxel_bee.py ... shining` → `bee_voxel_shining.glb` (**toda prateada e cromada**: o cromado é pintado — brilho branco em cima, linha escura de horizonte com um filete claro embaixo, listras quase pretas — mais estrelinhas sob o nó `Sparkles`; paleta escurecida com `glow()`) | ✅ no jogo, desenhada sem sombreamento. Ícones de todas as skins em `art/ui/bee_<skin>.png`, gerados por `tools/godot/render_bee_icons.gd` (rodar de novo se um modelo mudar) |
| Sol | `make_voxel_sun.py` → `sun_voxel.glb` (disco chato de cubos de 0,3 un. — fica a 135 un. de distância —, mesmo raio da esfera antiga, com miolo claro, borda mais quente e oito raios curtos; paleta pálida de propósito, para não competir com as flores amarelas; `glow()` na paleta) | ✅ no jogo (o material continua sendo criado em `view3d.gd`, para o sol sumir no pôr do sol) |
| Partículas ao pegar flor, estrelas e linha de recorde | sem modelo, feitas por código em `view3d.gd`: `_burst()` solta cubos de dois tamanhos exatos da grade (0,08 e 0,04); `_build_stars()` usa cubos de 1 ou 2 "cubos de tela" e 12 estrelas em cruz; `_build_record_line()` faz os traços com 6 cubos e escreve RECORD em letras de cubos 5×7 com sombra | ✅ no jogo |

## Estado da jogabilidade (valores atuais)
- **Abelha menor e mais rápida — todas** (TEST, pedido do usuário): `BEE_R 12.8` (era 16.0) e `H_SPEED 316` (era 275; antes 230) em `bee.gd`. O modelo já é construído nesse tamanho, com cubos iguais aos do mundo.
- **Skins de abelha** (`BEE_SKINS` em `main.gd`, todas só visuais): Bee (0), Rosy (25), Mint (60), Ice (100), Grape (150), Queen (220) e **Silver (300, a mais difícil — pedido do usuário)**. Ganha-se a skin no instante em que a partida chega ao score (`_check_bee_unlocks`), salva em `SaveData.unlocked_bees`; também conta como liberada se `best_score` já cobre o score.
- **Menu de abelhas** ("Choose your bee"): botão com o ícone da abelha na tela inicial e na de game over; grade de 3 colunas, a prateada sozinha na última linha; trancadas aparecem como silhueta com "Score N". Escolha salva em `SaveData.selected_bee`.
- **Aviso de desbloqueio**: faixa "<nome> unlocked!" por ~4 s + som de recorde + vibração, na primeira vez que o score chega ao valor da skin.
- **Vibração** (`_vibrate`): ao morrer, ao bater recorde e ao ganhar skin; botão liga/desliga no menu de pausa, ao lado do da música (`SaveData.vibration`). Precisa de `permissions/vibrate=true` no preset Android (`export_presets.cfg` não vai para o git).
- Velocidade de scroll `SCROLL_BASE 90` / `SCROLL_MAX 170` (TEST, era 78/148); rampa de dificuldade 35 s (TEST, era 50).
- Distância lateral máxima gap↔flor limitada a 200 px na dificuldade máxima (evita fileiras impossíveis).
- Morte: queda de 0,8 s (TEST, era 1,4), tremor de tela; "near miss" (raspou a 8 px da roseira) dá tremor leve + som.
- Replay: câmera espera 0,5 s após o 1º toque (1ª partida: 1 s).
- Linha tracejada "RECORD" no mundo, na altura da flor que bate o recorde.
- Fundo do horizonte sorteado por partida: colinas+montanhas (com árvores) ou cidade.

## Áudio
- Música e SFX são gerados/ajustados por código; a música teve um "tic" corrigido (fade no fim das notas).
- O usuário vai gerar sons novos no **ElevenLabs** (lista de prompts já entregue): `sfx_flap`, `sfx_collect` (nota única em Lá — o jogo sobe o tom a cada flor), `sfx_hit`, `sfx_near_miss`, `sfx_record`, `sfx_ui_tap`, `music_theme` (loop). Quando chegarem: trocar em `audio/` e ajustar os volumes (constantes `SFX_*_DB` em `main.gd`).

## Pendências
1. **Mundo 3D e interface já são voxel.** A interface nova foi feita de uma vez, a pedido do usuário, e aguarda a opinião dele (logo, botões, painéis, fonte).
3. A lua e o Júpiter aparecem um pouco mais pastel que nos renders (sem sombreamento o jogo mostra a cor do vértice como luz linear); o OVNI, a abelha prateada e o sol já têm a correção `glow()` na paleta — aplicar neles se o usuário quiser cores mais fortes.
4. Integrar os sons do ElevenLabs quando o usuário enviar.
