#!/usr/bin/env bash
# Instala los binarios de este repo en ~/.local/bin, para tenerlos en el PATH.
# No requiere sudo. Si ~/.local/bin no está en tu PATH, lo añade a ~/.zshrc.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${DEST:-$HOME/.local/bin}"
mkdir -p "$DEST"

for b in llama-cli llama-server llama-bench; do
  ln -sf "$HERE/bin/$b" "$DEST/$b"
  echo "==> $DEST/$b -> $HERE/bin/$b"
done

# Alias corto sin el sufijo, como ollama
ln -sf "$HERE/bin/llama-cli" "$DEST/llama"

case ":$PATH:" in
  *":$DEST:"*) echo "==> $DEST ya está en el PATH" ;;
  *)
    if grep -qs "$DEST" "$HOME/.zshrc"; then
      echo "==> $DEST ya figura en ~/.zshrc"
    else
      echo "export PATH=$DEST:\$PATH" >> "$HOME/.zshrc"
      echo "==> añadido a ~/.zshrc (abre una terminal nueva o ejecuta 'source ~/.zshrc')"
    fi
    ;;
esac

echo "==> prueba: llama --version"