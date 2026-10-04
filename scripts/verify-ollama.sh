#!/usr/bin/env bash
# Verifica el build de ollama en ollama-dist/.
# Salida: 0 si todo correcto, 1 si algún check falla.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$HERE/ollama-dist"
fail=0

echo "=== Archivos esenciales ==="
for f in ollama llama-server libggml-cpu-haswell.so libllama.so libmtmd.so; do
  if [ -e "$DIST/$f" ]; then
    echo "  OK    $f"
  else
    echo "  FALLA $f ausente"; fail=1
  fi
done

echo
echo "=== Symlinks de soname (el runtime los necesita) ==="
for l in libggml.so libllama.so libmtmd.so libggml-base.so; do
  if [ -L "$DIST/$l" ]; then
    echo "  OK    $l -> $(readlink "$DIST/$l")"
  else
    echo "  FALLA $l no es symlink (cp dereferenceo los symlinks)"; fail=1
  fi
done

echo
echo "=== Librerias resueltas (RUNPATH=\$ORIGIN, deben estar en el mismo dir) ==="
for bin in ollama llama-server; do
  n=$(cd "$DIST" && ldd "$bin" 2>&1 | grep -c 'not found' || true)
  if [ "$n" -eq 0 ]; then
    echo "  OK    $bin: todas las libs resueltas"
  else
    echo "  FALLA $bin: $n librerias sin resolver"; fail=1
  fi
done

echo
echo "=== AVX-512 ausente en la variant de CPU ==="
zmm=$(objdump -d "$DIST/libggml-cpu-haswell.so" 2>/dev/null | grep -c zmm || true)
if [ "$zmm" -eq 0 ]; then
  echo "  OK    haswell zmm=0"
else
  echo "  FALLA haswell tiene $zmm zmm (no debería, esta CPU no tiene AVX-512)"; fail=1
fi

echo
echo "=== AVX2/FMA presente ==="
ymm=$(objdump -d "$DIST/libggml-cpu-haswell.so" 2>/dev/null | grep -c ymm || true)
fma=$(objdump -d "$DIST/libggml-cpu-haswell.so" 2>/dev/null | grep -c vfmadd || true)
[ "$ymm" -gt 0 ] && echo "  OK    ymm: $ymm" || { echo "  FALLA ymm=0"; fail=1; }
[ "$fma" -gt 0 ] && echo "  OK    vfmadd: $fma" || { echo "  FALLA vfmadd=0"; fail=1; }

echo
echo "=== Sizes ==="
du -sh "$DIST" | sed 's/^/  /'

echo
[ "$fail" -eq 0 ] && echo "RESULTADO: todos los checks pasaron" || echo "RESULTADO: hay checks fallidos"
exit "$fail"