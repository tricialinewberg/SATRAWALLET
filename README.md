# SATRA WALLET

## Visão Geral

Satra é um aplicativo de celular disfarçado de calculadora nativa do sistema. Por fora, funciona como uma calculadora de verdade. Por dentro, é uma carteira Lightning (bitcoin) completa, criada para mulheres em situação de violência doméstica guardarem uma reserva financeira sem deixar rastro visível para quem monitora o celular delas.

---

## Problema

Controle financeiro é uma forma comum e pouco discutida de abuso doméstico. Agressores costumam monitorar extratos bancários, cartões, Pix e apps financeiros no celular da vítima. O desafio não é "segurança contra hackers", é invisibilidade social: o adversário tem acesso físico direto ao celular.

### Público-alvo

Satra é para qualquer mulher cujo dinheiro é controlado por outra pessoa — marido, companheiro, pai, ou qualquer figura de poder na relação.

Isso inclui:

- Mulheres em situação de violência doméstica que ainda convivem com o agressor
- Mulheres que trabalham e geram sua própria renda, mas não têm acesso real a ela — o parceiro controla salário, extrato, cartão ou decide como e quando o dinheiro pode ser gasto
- Pessoas planejando a saída de uma relação abusiva, que precisam de uma reserva financeira invisível pra viabilizar esse plano
- Rede de apoio (familiares, ONGs, assistentes sociais) que atuam com essas mulheres

O ponto em comum é a ausência de autonomia sobre a própria renda.

---

## Solução

### Fluxo de uso completo

#### Onboarding (primeiro acesso)
App instalado, estado "virgem" (sem PIN configurado). Uma sequência-mestra fixa digitada nesse estado abre, uma única vez, um modo de configuração. Nesse modo, a usuária define seu PIN pessoal (tipo 3221=). Depois de definido, a sequência-mestra deixa de funcionar (não pode mais reabrir a configuração).

**Código de acesso:** `21 + =` (número 21 seguido do botão de igual da calculadora)

#### Uso do dia a dia
App abre sempre como calculadora funcional de verdade. Digitar o PIN pessoal + = troca a tela pra UI real da carteira, mostrando saldo em sats, opção de receber e enviar. O PIN é o único método de acesso no dia a dia.

#### Configuração da chave física (uma única vez)
Numa tela própria de configuração ("Senha da chave física"), a usuária define uma senha e gera uma carteira de escape fixa — uma carteira separada da carteira do dia a dia, criada uma única vez. A seed dessa carteira é criptografada (Argon2id + AES-256-GCM) e gravada permanentemente num chip NFC/NTAG regravável, escondido num objeto do cotidiano (chaveiro, colar, etc.). O app confirma a gravação lendo a tag de volta e verificando o conteúdo antes de considerar a configuração concluída.

#### Botão de escape (modo de emergência)
Dentro da carteira, um controle de deslizar (swipe) discreto. Ao ser completado, dispara duas ações em paralelo:
- **Financeira:** envia todo o saldo da carteira do dia a dia pra essa carteira de escape fixa (já configurada previamente, sem precisar tocar na chave física nesse momento).
- **Alerta silencioso:** envia uma DM criptografada via Nostr (NIP-17, com gift wrap NIP-59) para rede de confiança previamente cadastrada, avisando que o escape foi ativado – sem precisar abrir nenhum outro app.

Depois de executado, o app volta sozinho para aparência de calculadora normal.

#### Chave física (NFC)
O chip NFC/NTAG guarda só a chave de acesso à carteira de escape – não o saldo (modelo "cartão de banco": o dinheiro não está no chip, o chip só autoriza acesso à conta). Todo o conteúdo é criptografado com senha antes de ser gravado – nenhuma tag Satra guarda a seed em texto puro. Esse chip é usado no momento de restaurar o acesso (em outro celular, depois de já estar segura) – não é usado no desbloqueio do dia a dia.

#### Herança
A usuária pode opcionalmente cadastrar um ou mais herdeiros (por npub Nostr) e um prazo de inatividade (ex: 6 meses, 1 ano). Se a carteira ficar sem uso além desse prazo, o app avisa o(s) herdeiro(s) via Nostr e inicia um período de carência. Se a usuária não voltar a usar o app durante essa carência, as informações de recuperação são liberadas ao herdeiro, protegidas pelo mesmo esquema de criptografia por senha usado na chave física.

### Identidade Visual

**Nome:** Satra (Satra Wallet) — nome curto, sonoro, com raiz derivada de "sats" (unidade do bitcoin).

**Paleta de cores:**
- Azul marinho (#0B2545): Texto de destaque, elementos principais
- Azul médio (#1B4F8C): Botões/ações primárias
- Azul claro (#A9D6E5): Acentos, elementos secundários
- Fundo (#F4F8FB): Fundo claro, leve tom azulado (não branco puro)

Critério geral: transmitir confiança e transparência (associação com azul), sem chamar atenção – nada saturado ou vibrante demais, já que o app precisa passar despercebido.

**Logo:**
![Satra Logo](https://github.com/user-attachments/assets/40a192b2-ad9b-4bf1-83db-734c1d9b6505)

### Telas do app

#### Onboarding

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

#### Carteira

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

#### Recuperação

![Transferência via NFC](assets/screens/TRANFERIR%20CHAVE%20FÍSICA%20PARA%20CARTEIRA.png)

---

## Stack de Tecnologia

- **Cross-platform:** Flutter
- **Lightning:** Implementado diretamente no app via Breez SDK (Spark) – sem depender de Nostr Wallet Connect (NWC) nem de infraestrutura própria rodando. O app é a carteira, ponta a ponta.
- **Lightning Address:** Usado pra receber pagamentos de forma simples (formato tipo algo@dominio.com)
- **Identidade Nostr:** Derivada deterministicamente da mesma seed da carteira Bitcoin (padrão NIP-06) – restaurar a carteira (por seed ou pela chave física) também restaura a mesma identidade Nostr e recupera a rede de confiança automaticamente
- **NIP-19:** Conversor de chaves — a carteira é convertida para chave Nostr portável usando o padrão NIP-19, permitindo portabilidade e interoperabilidade com outros clientes Nostr
- **NIP-17:** Alertas de emergência enviados como DMs criptografadas (protege inclusive metadados, ao contrário do NIP-04)
- **NIP-44:** Rede de confiança sincronizada entre dispositivos via evento criptografado publicado nos relays
- **NIP-78:** Backup do cofre de contatos sincronizado e criptografado em relays
- **NFC:** Chip NTAG regravável, guardando um envelope criptografado (Argon2id + AES-256-GCM) com a credencial de acesso – nunca a seed em texto puro
- **Criptografia:** Argon2id (19 MiB, 2+ iterações) + AES-256-GCM para envelope encryption
- **Armazenamento Seguro:** flutter_secure_storage ^10.3.1 (Android Keystore / iOS Keychain)

---

## Equipe

| Nome | Função | GitHub |
|------|--------|--------|
| Giovanna Gardinali | Front Developer | [@GioGardinali](https://github.com/GioGardinali) |
| Ingrid Gama | Back-end - Bitcoiner | [@raiosgama](https://github.com/raiosgama) |
| Trícia Linewberg | UX Designer - Bitcoiner | [@tricialinewberg](https://github.com/tricialinewberg) |

---

## Repositório e Links

- **GitHub:** [tricialinewberg/SATRAWALLET](https://github.com/tricialinewberg/SATRAWALLET)
- **Apresentação do Pitch:** 
  - Local: `apresentacao/satra-pitch.html`
  - Como acessar: Baixe todos os arquivos do repositório e abra `satra-pitch.html` em um navegador web
- **SDK e Recursos para Testes:**
  - [hack4freedom — SDK e Arquivos de Teste](https://1drv.ms/f/c/6e39028b5e01813a/IgCpXdsSQWASSb-gXhyG_1b6AbBm0f2hOFVWzP_zXTvsCSU)
  - Contém APK, protótipos de vídeo, imagens de interface e recursos para desenvolvimento

---

## Status

🚀 **Em Desenvolvimento**

- ✅ Prototipagem conceitual
- ✅ Design visual completo
- ✅ Apresentação de pitch
- 🔄 Implementação do core (Flutter + Breez SDK)
- ⏳ Integração Nostr (NIPs)
- ⏳ Testes de segurança
- ⏳ Validação com rede de apoio

### Como rodar

#### Configuração do ambiente

1. Clone o repositório:
```bash
git clone https://github.com/tricialinewberg/SATRAWALLET.git
cd SATRAWALLET
```

2. Configure as variáveis de ambiente no arquivo `.env` na raiz do projeto:
```
# Exemplo de .env
BREEZ_API_KEY=your_key_here
RELAY_URLS=wss://relay1.example.com,wss://relay2.example.com
```

3. Instale as dependências Flutter:
```bash
flutter pub get
```

4. Execute o aplicativo:
```bash
# Debug
flutter run

# Release (APK)
flutter build apk --release
```

---

## Próximos Passos

### 1. Confiabilidade do Escape
Fila de retentativas e confirmação de entrega para que transferências e alertas Nostr resistam a conexão instável, relays indisponíveis e encerramento do app.

### 2. Segurança Auditável
Modelo de ameaças, revisão independente de criptografia e testes de invasão para validar o disfarce, o armazenamento local e os fluxos de recuperação, além do aprimoramento da herança da carteira.

### 3. Validação com a Rede de Apoio
Co-criação com sobreviventes, assistentes sociais e organizações parceiras para testar linguagem, fluxo de escape e protocolos de acolhimento sem expor usuárias.

### 4. Recuperação Resiliente
Evolução da chave NFC com cópias cifradas, plano para perda do aparelho e recuperação assistida, sem concentrar a segurança em um único ponto.

---

**Desenvolvido durante Hack4Freedom São Paulo 2026**
