#!/usr/bin/env bash
# Reproduce el build nativo de llama.cpp para esta CPU.
# Ver ./README.md para qué se eligió cada flag.
set -euo pipefail

SRC_COMMIT="11fe02151f79c41d0d4af7da708755d73b9c0da6"   # tag b11382, ggml 0.25.3
BUILD_JOBS="${BUILD_JOBS:-$(nproc)}"
REPO_DIR="${REPO_DIR:-$HOME/src/llama.cpp}"

echo "==> cmake: $(command -v cmake || echo 'NO ENCONTRADO — instala cmake o exporta PATH con el portable')"
command -v cmake >/dev/null || { echo "cmake ausente; ver la sección 'Requisitos para reconstruir' del README"; exit 1; }

if [ ! -d "$REPO_DIR" ]; then
  echo "==> clonando llama.cpp en $REPO_DIR"
  git clone --depth 1 https://github.com/ggml-org/llama.cpp "$REPO_DIR"
fi

cd "$REPO_DIR"
if [ "$(git rev-parse HEAD)" != "$SRC_COMMIT" ]; then
  echo "==> nota: el repo está en $(git rev-parse --short HEAD), no en ${SRC_COMMIT:0:7}"
  echo "    para reproducible: git fetch --depth 1 origin $SRC_COMMIT && git checkout $SRC_COMMIT"
  echo "    o simplemente continúa: los flags nativos aplican igual a otros commits."
fi

echo "==> configurando (nativo: AVX2/FMA/F16C/BMI2, sin AVX-512)"
cmake -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_NATIVE=ON \
  -DGGML_AVX2=ON \
  -DGGML_FMA=ON \
  -DGGML_F16C=ON \
  -DGGML_BMI2=ON \
  -DGGML_OPENMP=ON \
  -DGGML_LTO=ON \
  -DGGML_BACKEND_DL=OFF \
  -DBUILD_SHARED_LIBS=OFF \
  -DLLAMA_CURL=OFF \
  -DLLAMA_BUILD_TESTS=OFF \
  -DCMAKE_C_FLAGS_RELEASE='-O3 -march=native -mtune=native' \
  -DCMAKE_CXX_FLAGS_RELEASE='-O3 -march=native -mtune=native'

echo "==> compilando con $BUILD_JOBS hilos (esto toma ~45 min en esta laptop)"
cmake --build build --config Release -j "$BUILD_JOBS"

echo "==> verificando que NO se emitió AVX-512 (debe ser 0)"
zmm=$(objdump -d build/bin/llama-cli | grep -c zmm || true)
echo "    zmm: $zmm  $([ "$zmm" -eq 0 ] && echo 'OK' || echo 'AVISO: hay código AVX-512')"
echo "    ymm: $(objdump -d build/bin/llama-cli | grep -c ymm || true)  (debe ser > 0)"

echo "==> listo: $REPO_DIR/build/bin"