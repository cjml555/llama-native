# Compilar ollama para i3-8130U

Ollama compilado desde fuente con el llama.cpp nativo de esta máquina. A diferencia
del build directo de llama.cpp (ver `../README.md`), aquí **no se puede usar
`-march=native`** — la razón es el obstacle que documenta abajo.

## Fuente

| | |
|---|---|
| ollama | commit `42e911b` ("docs: document image input for decision models") |
| llama.cpp | `b11382` / `11fe021`, el mismo de `bin/`, vía `FETCHCONTENT_SOURCE_DIR_LLAMA_CPP` |
| Go | 1.27.1 (portable, sin sudo) |
| Licencia | ollama: MIT · llama.cpp: MIT |

## El conflicto: GGML_NATIVE es incompatible con BACKEND_DL

Este es el hallazgo central de compilar ollama, y costó tres intentos fallidos.

1. **Ollama exige `GGML_BACKEND_DL=ON`.** Usa el backend dinámico de ggml. Con
   `GGML_BACKEND_DL=OFF` el configure falla:

   ```
   CMake Error at ggml/src/CMakeLists.txt:489 (message):
     GGML_CPU_ALL_VARIANTS requires GGML_BACKEND_DL
   ```

2. **Pero ggml rechaza `GGML_NATIVE=ON` cuando `BACKEND_DL` está activo:**

   ```
   CMake Error at ggml/src/ggml-cpu/CMakeLists.txt:415 (message):
     GGML_NATIVE is not compatible with GGML_BACKEND_DL, consider using
     GGML_CPU_ALL_VARIANTS
   ```

O sea: no hay combinación que permita `-march=native` en ollama. La razón está en
`ggml-cpu/CMakeLists.txt`: con backend dinámico, cada variante de CPU se compila
como una biblioteca separada, y `-march=native` produciría N bibliotecas idénticas
conflags distintos para cada una — sin sentido.

**La solución** es poner los flags de instrucción uno por uno, que es lo que ggml
espera en ese modo:

```
-DGGML_NATIVE=OFF
-DGGML_AVX2=ON -DGGML_FMA=ON -DGGML_F16C=ON -DGGML_BMI2=ON
-DGGML_AVX512=OFF -DGGML_AVX512F=OFF -DGGML_AVX512_VBMI=OFF
-DGGML_AVX512_VNNI=OFF -DGGML_AVX512_BF16=OFF
-DGGML_AMX_TILE=OFF
-DGGML_OPENMP=ON -DGGML_LTO=ON -DGGML_BACKEND_DL=ON
-DCMAKE_C_FLAGS_RELEASE='-O3 -march=x86-64-v3 -mtune=native'
```

`x86-64-v3` es exactamente el conjunto de esta CPU (AVX2 + FMA + F16C + BMI2) y
cubre la mayoría de x86-64 modernos, así que el build también corre en otras
máquinas sin recompilar.

## Las 14 variants de CPU

Con `BACKEND_DL=ON` se compilan 14 backends de CPU: haswell, ivybridge,
sandybridge, piledriver, cascadelake, cooperlake, cannonlake, skylakex, icelake,
sapphirerapids, alderlake, zen4, x64, sse42.

Verificado con objdump cuáles contienen AVX-512 (`zmm`):

| Sin AVX-512 (zmm=0) | Con AVX-512 (zmm>13 000) |
|---|---|
| **haswell** ← usa esta CPU | cannonlake, skylakex |
| ivybridge, sandybridge, piledriver | cascadelake, cooperlake |
| x64, sse42 | icelake, sapphirerapids |
| alderlake | zen4 |

**Esta distribución incluye solo `libggml-cpu-haswell.so`** (1.4 MB), que es la
variant correcta para i3-8130U. Las otras 13 se descartaron:

- 7 contienen instrucciones AVX-512 que esta CPU no tiene
- 6 son para CPUs más antiguas, superseded por haswell

El dispatcher selecciona la variant por CPUID en tiempo de ejecución, así que
incluir solo haswell es seguro y correcto. **Verificado**: con solo esa variant,
`ollama run` genera correctamente a 9.65 t/s.

> Si compilas para una CPU con AVX-512, cambia qué variant copias a `ollama-dist/`.
> Verifica la correcta con `objdump -d <variant> | grep -c zmm` — debe ser 0 salvo
> que tu CPU realmente tenga AVX-512.

## Estructura de `ollama-dist/`

Todo en un solo directorio plano, sin subcarpetas:

```
ollama-dist/
├── ollama                    # binario Go, 37 MB
├── llama-server              # runner de inferencia
├── llama-quantize
├── libggml-cpu-haswell.so    # único backend de CPU incluido
├── libggml{,-base}.so*       # symlink -> .so.0.25.3
├── libllama{,-common}.so*    # symlink -> .so.0.5.0
├── libmtmd.so*               # symlink -> .so.0.5.0
├── libllama-server-impl.so
├── libllama-quantize-impl.so
└── *LICENSE
```

**Las libs van en el mismo directorio que los binarios, no en `lib/`.** El
`RUNPATH` de los ejecutables es `$ORIGIN`, que resuelve al directorio del propio
binario. Si pones las libs en un subdirectorio, el runner falla con:

```
Error: llama-server process has terminated: exit status 127
```

Los symlinks `.so` son necesarios: el runtime busca `libggml.so.0` por su soname,
no por el nombre con versión completa.

## Uso

```bash
# Servidor (desde el directorio ollama-dist, para que $ORIGIN resuelva)
cd ollama-dist && ./ollama serve

# En otra terminal
./ollama run --think=false qwen3-local 'tu pregunta'
```

### Crear un modelo desde un GGUF

Ollama **no** acepta un GGUF directo en `create`; necesita un Modelfile:

```
FROM /ruta/al/modelo.gguf

TEMPLATE """{{- if .System }}<|im_start|>system
{{ .System }}<|im_end|>
{{ end }}{{- if .Prompt }}<|im_start|>user
{{ .Prompt }}<|im_end|>
{{ end }}<|im_start|>assistant
{{ .Response }}<|im_end|>

"""

PARAMETER num_ctx 2048
PARAMETER temperature 0.7
PARAMETER top_p 0.8
PARAMETER top_k 20
PARAMETER repeat_penalty 1.05
PARAMETER num_predict 256
```

```bash
./ollama create qwen3-local -f Modelfile
./ollama list
```

### `--think=false` es obligatorio en Qwen3

Sin ese flag, ollama imprime el razonamiento del modelo (en inglés) antes de la
respuesta. Es el mismo problema que con `llama-cli` directo, resuelto aquí por el
propio ollama en vez del chat template.

En el log del servidor se ve el efecto: `thinking = 1` por defecto en el init del
chat template.

## Rendimiento medido

Servidor en esta máquina, Qwen3-1.7B Q4_K_M, contexto 2048:

```
prompt eval time = 607.59 ms / 17 tokens (35.74 ms per token, 27.98 tokens per second)
eval time       = 414.32 ms /  5 tokens (103.58 ms per token,  9.65 tokens per second)
```

En corridas más largas se estabiliza en **10.2–10.8 t/s** de generación, con
`n_threads = 2` y KV cache de 224 MiB. Coincide con los 11.4 t/s medidos con
`llama-bench` sobre el mismo modelo — la diferencia es el overhead del protocolo
entre ollama y su runner.

El prompt processing (~25–28 t/s) es más rápido que la generación, igual que en
llama.cpp directo: la generación es memory-bound.

## Reconstruir

```bash
export PATH="$HOME/.local/opt/go/bin:$PATH"
git clone --depth 1 https://github.com/ollama/ollama ~/src/ollama

cmake -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DFETCHCONTENT_SOURCE_DIR_LLAMA_CPP="$HOME/src/llama.cpp" \
  -DGGML_NATIVE=OFF \
  -DGGML_AVX2=ON -DGGML_FMA=ON -DGGML_F16C=ON -DGGML_BMI2=ON \
  -DGGML_AVX512=OFF -DGGML_AVX512F=OFF -DGGML_AVX512_VBMI=OFF \
  -DGGML_AVX512_VNNI=OFF -DGGML_AVX512_BF16=OFF -DGGML_AMX_TILE=OFF \
  -DGGML_OPENMP=ON -DGGML_LTO=ON -DGGML_BACKEND_DL=ON \
  -DCMAKE_C_FLAGS_RELEASE='-O3 -march=x86-64-v3 -mtune=native' \
  -DCMAKE_CXX_FLAGS_RELEASE='-O3 -march=x86-64-v3 -mtune=native'

cmake --build build --config Release -j 4   # ~30 min: C++ de llama.cpp
cd build && go build -o bin/ollama .       # ~4 min
```

**Si cambias los flags de ggml**, borra `build/` antes de re-configurar: la cache
de CMake conserva valores del intento anterior y `make` no los ve.

Si necesitas regenerar `ollama-dist/`, copia desde `build/lib/ollama/` (las libs
originales con sus symlinks intactos) y descarta las variants de CPU que no te
sirvan.