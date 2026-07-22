# SATRA WALLET
Satra é um aplicativo de celular disfarçado de calculadora nativa do sistema. Por fora, funciona como uma calculadora de verdade. Por dentro, é uma carteira Lightning (bitcoin) completa, criada para mulheres em situação de violência doméstica guardarem uma reserva financeira sem deixar rastro visível para quem monitora o celular delas.

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

Depois de executado, o app volta sozinho para aparência de calculadora normal.

### Chave física (NFC)
O chip NFC/NTAG guarda só a chave de acesso à carteira de escape – não o saldo (modelo "cartão de banco": o dinheiro não está no chip, o chip só autoriza acesso à conta). Todo o conteúdo é criptografado com senha antes de ser gravado – nenhuma tag Satra guarda a seed em texto puro. Esse chip é usado no momento de restaurar o acesso (em outro celular, depois de já estar segura) – não é usado no desbloqueio do dia a dia.

### Herança

A usuária pode opcionalmente cadastrar um ou mais herdeiros (por npub Nostr) e um prazo de inatividade (ex: 6 meses, 1 ano). Se a carteira ficar sem uso além desse prazo, o app avisa o(s) herdeiro(s) via Nostr e inicia um período de carência. Se a usuária não voltar a usar o app durante essa carência, as informações de recuperação são liberadas ao herdeiro, protegidas pelo mesmo esquema de criptografia por senha usado na chave física.

# Arquitetura Técnica
### Stack
Cross-platform: Flutter

Lightning: implementado diretamente no app via Breez SDK (Spark) – sem depender de Nostr Wallet Connect (NWC) nem de infraestrutura própria rodando. O app é a carteira, ponta a ponta.

Lightning Address: usado pra receber pagamentos de forma simples (formato tipo algo@dominio.com).

Identidade Nostr: derivada deterministicamente da mesma seed da carteira Bitcoin (padrão NIP-06) – restaurar a carteira (por seed ou pela chave física) também restaura a mesma identidade Nostr e recupera a rede de confiança automaticamente.

Nostr – canal de socorro: alerta de escape enviado via DM criptografada usando NIP-17 (protege inclusive metadados, ao contrário do NIP-04), publicado em paralelo em múltiplos relays.

Rede de confiança: sincronizada entre dispositivos via evento criptografado (NIP-44) publicado nos relays, não fica presa só ao armazenamento local do celular.

NFC: chip NTAG regravável, guardando um envelope criptografado (Argon2id + AES-256-GCM) com a credencial de acesso – nunca a seed em texto puro. Escrita verificada com um ciclo de escrever → reler → validar antes de confirmar sucesso.
# Identidade Visual
### Nome
Satra (Satra Wallet): nome curto, sonoro, com raiz derivada de "sats" (unidade do bitcoin).

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

| Splash | Configuração do PIN |
|---|---|
| ![Splash](assets/screens/SPLASH.png) | ![Configuração do PIN](assets/screens/PRIMEIROS%20PASSOS%20-%205.png) |

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
