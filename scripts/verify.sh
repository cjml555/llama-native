#!/usr/bin/env bash
# Verifica que los binarios de este repo estén compilados para esta CPU.
# Salida: 0 si todo correcto, 1 si algún check falla.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$HERE/bin/llama-cli"
fail=0

echo "=== CPU ==="
lscpu | grep -E 'Model name|^CPU\(s\):|Flags' | sed 's/^/  /' | cut -c1-200

echo
echo "=== AVX-2 / FMA presentes en el binario ==="
for pat in ymm vfmadd; do
  n=$(objdump -d "$CLI" 2>/dev/null | grep -c "$pat" || true)
  if [ "$n" -gt 0 ]; then echo "  OK    $pat: $n"; else echo "  FALLA $pat: 0"; fail=1; fi
done

echo
echo "=== AVX-512 ausente (esta CPU no lo tiene) ==="
zmm=$(objdump -d "$CLI" 2>/dev/null | grep -c zmm || true)
if [ "$zmm" -eq 0 ]; then echo "  OK    zmm: 0"; else echo "  FALLA zmm: $zmm"; fail=1; fi

echo
echo "=== El binario corre en esta máquina ==="
if "$CLI" --version >/dev/null 2>&1; then
  echo "  OK    $("$CLI" --version 2>&1 | head -1)"
else
  echo "  FALLA no se puede ejecutar (¿binario de otra arquitectura?)"; fail=1
fi

echo
[ "$fail" -eq 0 ] && echo "RESULTADO: todos los checks pasaron" || echo "RESULTADO: hay checks fallidos"
exit "$fail"