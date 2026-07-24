#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="$project_dir/config.json"

if [[ ! -f "$config_file" ]]; then
  echo "Erro: config.json não encontrado."
  echo "Copie config.example.json, preencha BREEZ_API_KEY e tente novamente."
  exit 1
fi

if grep -q 'COLE_SUA_CHAVE_BREEZ_AQUI' "$config_file"; then
  echo "Erro: substitua o placeholder de BREEZ_API_KEY em config.json."
  exit 1
fi

cd "$project_dir"
exec flutter build apk \
  --debug \
  --dart-define-from-file="$config_file"
