# SATRA WALLET
Satra é um aplicativo de celular disfarçado de calculadora nativa do sistema. Por fora, inicia diretamente em uma calculadora funcional, sem tela de marca ou imagem de splash. Por dentro, é uma carteira Lightning (bitcoin) completa, criada para mulheres em situação de violência doméstica guardarem uma reserva financeira sem deixar rastro visível para quem monitora o celular delas.

> Status: protótipo funcional em evolução. O app já possui fluxos reais de carteira, recuperação e herança, mas qualquer uso com fundos deve ser feito somente após testes independentes e revisão de segurança.

# O Problema
Controle financeiro é uma forma comum e pouco discutida de abuso doméstico. Agressores costumam monitorar extratos bancários, cartões, Pix e apps financeiros no celular da vítima. O desafio não é "segurança contra hackers", é invisibilidade social: o adversário tem acesso físico direto ao celular.

# Público
Mulheres em situação de violência doméstica, ainda convivendo com o agressor;
Mulheres em processo de planejamento de saída de uma relação abusiva;

# Fluxo de uso completo:
### Onboarding (primeiro acesso)
App instalado, estado "virgem" (sem PIN configurado). Uma sequência-mestra fixa digitada nesse estado abre, uma única vez, um modo de configuração. Nesse modo, a usuária define seu PIN pessoal (tipo 3221=). Depois de definido, a sequência-mestra deixa de funcionar ( não pode mais reabrir a configuração.)
Uso do dia a dia

App abre sempre como calculadora funcional de verdade. Digitar o PIN pessoal + = troca a tela pra UI real da carteira, mostrando saldo em sats, opção de receber e enviar. O PIN é o único método de acesso no dia a dia.

### Configuração da chave física (uma única vez)
Numa tela própria de configuração ("Senha da chave física"), a usuária define uma senha e gera uma carteira de escape fixa — uma carteira separada da carteira do dia a dia, criada uma única vez. A seed dessa carteira é criptografada (Argon2id + AES-256-GCM) e gravada permanentemente num chip NFC/NTAG regravável, escondido num objeto do cotidiano (chaveiro, colar, etc.). O app confirma a gravação lendo a tag de volta e verificando o conteúdo antes de considerar a configuração concluída.

### Botão de escape (modo de emergência)

Dentro da carteira, um controle de deslizar (swipe) discreto. Ao ser completado, dispara duas ações em paralelo:
Financeira: envia todo o saldo da carteira do dia a dia pra essa carteira de escape fixa (já configurada previamente, sem precisar tocar na chave física nesse momento).
Alerta silencioso: envia uma DM criptografada via Nostr (NIP-17, com gift wrap NIP-59) para rede de confiança previamente cadastrada, avisando que o escape foi ativado – sem precisar abrir nenhum outro app.

Depois de executado, o app volta sozinho para aparência de calculadora normal. O PIN e a biometria são caminhos independentes: tocar `=` verifica o PIN; segurar `=` pode abrir a biometria quando ela estiver ativada.

### Chave física (NFC)
O chip NFC/NTAG guarda só a chave de acesso à carteira de escape – não o saldo (modelo "cartão de banco": o dinheiro não está no chip, o chip só autoriza acesso à conta). Todo o conteúdo é criptografado com senha antes de ser gravado – nenhuma tag Satra guarda a seed em texto puro. Esse chip é usado no momento de restaurar o acesso (em outro celular, depois de já estar segura) – não é usado no desbloqueio do dia a dia.

### Herança

A usuária pode opcionalmente cadastrar um ou mais herdeiros (por npub Nostr) e um prazo de inatividade (ex: 6 meses, 1 ano). Se a carteira ficar sem uso além desse prazo, o app avisa o(s) herdeiro(s) via Nostr e inicia um período de carência. Se a usuária não voltar a usar o app durante essa carência, as informações de recuperação são liberadas ao herdeiro, protegidas pelo mesmo esquema de criptografia por senha usado na chave física.

#### Como funciona a liberação da herança (real e descentralizada)

A herança é desenhada para funcionar **mesmo se o app da titular nunca mais abrir** — nenhuma parte da liberação depende do celular da titular estar vivo:

1. **Em vida (configuração):** ao ativar a herança, o app cifra a seed com a senha de liberação (Argon2id + AES-256-GCM) e **pré-publica** o envelope cifrado nos relays Nostr — um evento por herdeiro, protegido por NIP-44. Publica também um heartbeat assinado (kind 30078) com `valid_until` e prazo de carência.
2. **Aviso ao herdeiro:** quando o titular fica inativo, o heartbeat para de ser renovado. O herdeiro pode acompanhar o silêncio do npub da titular em **qualquer cliente Nostr** (Damus, Primal, Amethyst) — prova pública e auditável.
3. **Decifração:** o herdeiro obtém o envelope (do seu cliente Nostr) e a senha de liberação (combinada em vida, ex.: num cartão selado). Decifra com um dos caminhos abaixo — nenhum deles exige que o app Satra da titular esteja instalado ou funcionando.

#### Como o herdeiro decifra (caminhos disponíveis)

| Caminho | Precisa instalar Satra? | Como acessar |
|---|---|---|
| **Dentro do app Satra** | Sim | O herdeiro abre “Decifrar herança”, cola o envelope recebido via Nostr e informa a senha. |
| **Sequência na calculadora** | Sim, instala o app | No estado virgem (sem PIN), digitar a sequência de herdeiro e `=` abre direto a tela "Decifrar herança". |
| **Menu lateral** | Sim, se já for usuário Satra | Desbloqueia com seu próprio PIN → menu → "Decifrar herança". |

Atualmente a decifração oficial acontece dentro do próprio app Satra. A pasta `inheritance-decryptor/` contém um protótipo estático não publicado; ela não deve ser apresentada ao herdeiro como um site disponível até que seja hospedada, auditada e tenha uma URL oficial.

#### O que a titular entrega ao herdeiro (em vida)

- **npub da titular** — para o herdeiro encontrar o heartbeat/silêncio no Nostr
- **app Satra instalado** — para abrir a tela de decifração
- **Senha de liberação** — necessária para decifrar (não está nos relays)
- Opcionalmente: a sequência de herdeiro `589301` se for usar o app Satra

Recomenda-se entregar tudo num cartão físico selado, guardado pelo herdeiro, para abrir somente quando o Nostr da titular ficar mudo pelo prazo combinado.

# Arquitetura Técnica
### Stack
Cross-platform: Flutter

Lightning: implementado diretamente no app via Breez SDK (Spark) – sem depender de Nostr Wallet Connect (NWC) nem de infraestrutura própria rodando. O app é a carteira, ponta a ponta.

Lightning Address: usado para receber pagamentos de forma simples (formato tipo algo@dominio.com), com resolução LNURL-pay/LUD-16. O app também trabalha com invoices BOLT11, endereços e invoices Spark e endereços Bitcoin on-chain.

Identidade Nostr: derivada deterministicamente da mesma seed da carteira Bitcoin (padrão NIP-06) – restaurar a carteira (por seed ou pela chave física) também restaura a mesma identidade Nostr e recupera a rede de confiança automaticamente.

Nostr – canal de socorro: alerta de escape enviado via DM criptografada usando NIP-17 (protege inclusive metadados, ao contrário do NIP-04), publicado em paralelo em múltiplos relays.

Rede de confiança: sincronizada entre dispositivos via evento criptografado (NIP-44) publicado nos relays, não fica presa só ao armazenamento local do celular.

NFC: chip NTAG regravável, guardando um envelope criptografado (Argon2id + AES-256-GCM) com a credencial de acesso – nunca a seed em texto puro. Escrita verificada com um ciclo de escrever → reler → validar antes de confirmar sucesso.

### NIPs e padrões usados

- **NIP-06** — derivação determinística da identidade Nostr a partir da frase BIP-39 da carteira.
- **NIP-17** — mensagens privadas modernas usadas nos alertas de escape e nos avisos aos herdeiros.
- **NIP-44** — cifragem de contatos, envelopes de herança e sincronização entre dispositivos.
- **NIP-59** — gift wrap dos DMs NIP-17 para reduzir exposição de metadados.
- **NIP-78** — eventos replaceable `kind 30078` para dados de aplicação, heartbeats e envelopes publicados nos relays.
- **NIP-19** — representação e validação de `npub` usado nos contatos e herdeiros.
- **BIP-39/BIP-32** — frase de recuperação e material determinístico das chaves.
- **LNURL-pay/LUD-16 e BOLT11** — Lightning Address, invoices e pagamentos Lightning.

O aplicativo não usa Nostr Wallet Connect (NWC): a conexão Lightning fica no próprio Breez SDK. NIPs são usados para identidade, mensagens e sincronização, não para custodiar o saldo.

## O que a wallet faz hoje

- inicia como calculadora discreta e abre a carteira por PIN ou biometria;
- conecta ao Breez SDK Spark e mostra saldo real em sats e conversão fiat;
- recebe por Lightning Address, QR/invoice e endereço Bitcoin on-chain;
- envia para invoice Lightning/BOLT11, Lightning Address, Spark e endereço on-chain;
- permite escolher moeda fiat, ocultar saldo e configurar bloqueio ao sair do app;
- possui carteira de escape fixa com envio do saldo por gesto discreto;
- envia alerta criptografado à rede de confiança via Nostr;
- grava e recupera a credencial da carteira de escape em NFC, sempre cifrada;
- sincroniza contatos confiáveis e identidade Nostr após restauração;
- oferece herança com heartbeat, período de carência, múltiplos herdeiros e decifração dentro do próprio app;
- inclui backup por frase de recuperação e restauração em outro aparelho.

## Próximos passos

1. **Rede P2P opcional:** criar uma camada de descoberta e transporte entre dispositivos (por exemplo, libp2p/WebRTC com relay fallback), mantendo o Nostr como canal assíncrono e sem expor seed ou saldo.
2. **Testes de recuperação ponta a ponta:** automatizar cenários com cartão NFC real, restauração em aparelho limpo e rotação de PIN/biometria.
3. **Auditoria de segurança:** revisar criptografia, armazenamento seguro, escape sweep, herança e o modelo de ameaça antes de qualquer distribuição ampla.
4. **Resiliência offline:** melhorar filas locais, retries e confirmação visual quando relays, Breez ou a rede estiverem indisponíveis.
5. **Privacidade operacional:** reduzir metadados, oferecer relays configuráveis e documentar claramente o que é observado por Breez, Nostr e pelo provedor de Lightning Address.
6. **Qualidade de produto:** separar telas e serviços grandes, adicionar testes de integração e preparar builds assinados/reprodutíveis.
# Identidade Visual
### Nome
Satra (Satra Wallet): nome curto, sonoro, com raiz derivada de "sats" (unidade do bitcoin).

## Configuração local da Breez

Copie `config.example.json` para `config.json`, preencha `BREEZ_API_KEY` e execute:

```bash
flutter run --dart-define-from-file=config.json
```

O `config.json` é ignorado pelo Git. A chave ainda fica presente no APK compilado,
como qualquer credencial necessária por um aplicativo móvel, e não deve ser
tratada como um segredo impossível de extrair.

Os atalhos do projeto já usam o `config.json` automaticamente:

```bash
./tool/run_android.sh 13012704CA000805
./tool/build_debug_apk.sh
```

## Como instalar, executar e testar

### Pré-requisitos

- Flutter estável compatível com Dart 3;
- Android Studio/SDK e `adb` para testar em Android;
- um aparelho Android com NFC se quiser testar a chave física;
- uma chave API da Breez Spark para criar a carteira e movimentar fundos;
- Git para baixar o projeto.

### Baixar o projeto e as dependências

```bash
git clone <url-do-repositorio>
cd SATRAWALLET
flutter pub get
```

O `flutter pub get` baixa as dependências declaradas em `pubspec.yaml`, incluindo o SDK Flutter do Breez, Nostr, NFC, armazenamento seguro, câmera e QR Code.

### Configurar a chave Breez

Para desenvolvimento local, copie o template e preencha a chave. Nunca versione a chave real:

```bash
cp config.example.json config.json
# edite config.json e preencha BREEZ_API_KEY
flutter run --dart-define-from-file=config.json
```

Para usar os scripts do projeto (já aplicam o `--dart-define-from-file`):

```bash
./tool/run_android.sh <serial-do-aparelho>
```

`config.json` é ignorado pelo Git. O arquivo de exemplo contém apenas um placeholder.

### Executar no Android

```bash
adb devices
flutter run -d <serial-do-aparelho> --dart-define-from-file=config.json
```

O app abre como calculadora. No primeiro uso, digite `21` e toque em `=` para criar o PIN. Depois, digite o PIN e toque em `=` para abrir a carteira. A biometria, quando ativada no menu, é aberta segurando `=`.

### Gerar APK para teste

```bash
flutter build apk --debug --dart-define-from-file=config.json
```

O APK fica em `build/app/outputs/flutter-apk/app-debug.apk`.

Para um APK de usuário/teste manual:

```bash
flutter build apk --release --dart-define-from-file=config.json
```

O APK fica em `build/app/outputs/flutter-apk/app-release.apk`. Builds release locais usam a configuração de assinatura disponível no projeto; para distribuição pública, configure uma chave de assinatura própria.

### Instalar no aparelho

```bash
adb -s <serial-do-aparelho> install -r build/app/outputs/flutter-apk/app-release.apk
```

Se a instalação anterior usar outro `applicationId` ou assinatura, desinstale a versão antiga conscientemente: isso pode apagar o armazenamento seguro local da wallet.

### Rodar análise e testes

```bash
flutter analyze
flutter test
```

Os testes cobrem calculadora/PIN, criptografia da chave NFC, derivação Nostr, herança, contatos confiáveis e estados de escape. A leitura e gravação física do NFC ainda precisam de um cartão e aparelho compatíveis.

### Paleta de cores
Azul marinho (#0B2545): Texto de destaque, elementos principais
Azul médio (#1B4F8C): Botões/ações primárias
Azul claro (#A9D6E5): Acentos, elementos secundários
Fundo (#F4F8FB) Fundo claro, leve tom azulado (não branco puro)

Critério geral: transmitir confiança e transparência (associação com azul), sem chamar atenção – nada saturado ou vibrante demais, já que o app precisa passar despercebido.

### Logo

<img width="976" height="362" alt="Vector (1)" src="https://github.com/user-attachments/assets/40a192b2-ad9b-4bf1-83db-734c1d9b6505" />


# Telas do app

### Onboarding

O app não mostra splash de marca: abre diretamente na calculadora. A sequência de primeiro acesso leva à tela compacta de criação do PIN; a opção “Trocar PIN” usa a mesma lógica com título e instruções próprias.

![Configuração do PIN](assets/screens/PRIMEIROS%20PASSOS%20-%205.png)

<details>
<summary>Ver progressão do design (5 estados)</summary>

![PIN vazio](assets/screens/PRIMEIROS%20PASSOS.png)
![PIN 1 dígito](assets/screens/PRIMEIROS%20PASSOS%20-%202.png)
![PIN 2 dígitos](assets/screens/PRIMEIROS%20PASSOS%20-%203.png)
![PIN 3 dígitos](assets/screens/PRIMEIROS%20PASSOS%20-%204.png)
![PIN completo](assets/screens/PRIMEIROS%20PASSOS%20-%205.png)

</details>

### Carteira

| Wallet Home | Menu |
|---|---|
| ![Wallet Home](assets/screens/HOME.png) | ![Menu](assets/screens/MENU.png) |

| Receber | Confirmação de escape |
|---|---|
| ![Receber](assets/screens/RECEBER%20QRCODE.png) | ![Confirmação do escape](assets/screens/CONFIRMAÇÃO.png) |

<details>
<summary>Ver detalhes da wallet (saldo oculto, popup de escape, swipe completo)</summary>

![Saldo oculto](assets/screens/HOME%20-%202.png)
![Popup de escape](assets/screens/HOME%20-%20pop%20up.png)
![Swipe completo](assets/screens/HOME%20-%20swipe.png)

</details>

### Recuperação

![Transferência via NFC](assets/screens/TRANFERIR%20CHAVE%20FÍSICA%20PARA%20CARTEIRA.png)
