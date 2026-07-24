# Satra · Decifrador de herança (web)

Página estática que decifra o envelope de herança pré-publicado pela Satra
Wallet nos relays Nostr. Roda 100% no navegador do herdeiro — não precisa
instalar o app Satra.

## Por que existe

A herança da Satra é honesta e descentralizada: o titular cifra a seed com
uma senha de liberação e publica o envelope em Nostr (NIP-44 por herdeiro).
Quando o titular fica inativo, o herdeiro pega o envelope no seu cliente
Nostr (Damus, Primal, Amethyst...) e decifra aqui com a senha que recebeu em
vida (num cartão selado, por exemplo).

Este decifrador existe para que a herança **não dependa do app Satra
continuar nas lojas**. Mesmo se o app for descontinuado, enquanto esta
página existir em algum lugar, o herdeiro consegue recuperar a carteira.

## Como hospedar (GitHub Pages)

O deploy é **automático**: qualquer push para `main` que altere arquivos em
`inheritance-decryptor/` dispara o workflow
`.github/workflows/deploy-decryptor.yml`, que publica a pasta no GitHub Pages.

Para habilitar manualmente na primeira vez:
1. Vá em **Settings → Pages**
2. Source: **GitHub Actions**
3. Salve. O próximo push para `main` que altere o decifrador publica
   automaticamente em `https://<usuario>.github.io/SATRAWALLET/`

O `index.html` é self-contained (sem build). Para evitar confiar num CDN
de terceiros, baixe
[`argon2-bundled.min.js`](https://cdn.jsdelivr.net/npm/argon2-browser@1.18.0/dist/argon2-bundled.min.js)
para esta pasta e troque o `<script src=...>` para o caminho local.

## Formato do envelope

O envelope é JSON, produzido por `lib/services/nfc_credential_crypto.dart`
(no app) e lido aqui:

```json
{
  "version": 1,
  "walletType": "breez-spark",
  "network": "mainnet",
  "kdf": "argon2id",
  "kdfMemory": 19456,
  "kdfIterations": 3,
  "kdfParallelism": 1,
  "salt": "<base64, 16 bytes>",
  "nonce": "<base64>",
  "ciphertext": "<base64, ciphertext + tag>"
}
```

Camada de cripto: **Argon2id** (19 MiB, 3 iterações, paralelismo 1) → chave
AES-256-GCM. O tag de autenticação (16 bytes) é concatenado ao fim do
`ciphertext`, igual ao lado Dart.

## Segurança

- A decifração nunca envia nada pela rede — a biblioteca Argon2 (WASM) é
  self-hosted junto com a página, sem dependência de CDN externa.
- Senha errada e dado corrompido produzem a mesma mensagem genérica (não
  distinguível), igual ao `NfcCredentialException` do app.
- Código aberto. Audite em `lib/services/nfc_credential_crypto.dart`.
