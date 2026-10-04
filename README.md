# llama.cpp compilado nativo para i3-8130U

Binarios de [llama.cpp](https://github.com/ggml-org/llama.cpp) compilados con optimizaciones
específicas para esta laptop (Intel Core i3-8130U "Whiskey Lake"), listos para inferencia local
de modelos GGUF en CPU.

## Dos builds en este repo

| Directorio | Qué es | Tamaño |
|---|---|---|
| `bin/` | llama.cpp directo — `llama-cli`, `llama-server`, `llama-bench` | 51 MB |
| `ollama-dist/` | ollama compilado, con su runner y las libs de ggml | 71 MB |

Los builds **no son intercambiables**. `bin/llama-cli` usa `-march=native` de
verdad; `ollama-dist/` no puede, porque ollama exige backend dinámico y ggml lo
prohíbe con `GGML_NATIVE`. El detalle está en
[`ollama-dist/README.md`](ollama-dist/README.md), que documenta ese conflicto y las
14 variants de CPU que compila.

## Qué es esta máquina

| | |
|---|---|
| CPU | Intel Core i3-8130U @ 2.20 GHz (2 núcleos físicos, 4 hilos) |
| Arquitectura | x86_64, familia 6 modelo 142 stepping 10 |
| SIMD disponible | AVX, AVX2, FMA, F16C, BMI1, BMI2, SSE4.2 |
| SIMD **no** disponible | **AVX-512, AMX** — no compilar con esos flags |
| RAM | 11 GiB (típicamente 3–7 GB libres) |
| Swap | 13 GiB |
| SO | Manjaro, kernel 7.1.13-2 |
| Compilador | GCC 16.2.1 |

El techo real de esta CPU son ~12 t/s en modelos de 1.7B. Ver "Límites reales" más abajo.

## Build

Compilado desde el commit `11fe02151f79c41d0d4af7da708755d73b9c0da6` (tag `b11382`,
ggml 0.25.3) con:

```
-DGGML_NATIVE=ON          # detección automática de la CPU
-DGGML_AVX2=ON            # vectorización de 256 bits
-DGGML_FMA=ON             # FMA de 3 operandos (acumula sin instrucción extra)
-DGGML_F16C=ON            # conversión half<->float instantánea
-DGGML_BMI2=ON            # manipulación de bits para cuellos de deserialización
-DGGML_OPENMP=ON          # multihilo, 4 hilos por defecto
-DGGML_LTO=ON             # optimización en tiempo de enlazado
-DGGML_BACKEND_DL=OFF     # enlace estático del backend CPU
-DBUILD_SHARED_LIBS=OFF   # binarios autónomos
-DCMAKE_BUILD_TYPE=Release
-DCMAKE_C_FLAGS_RELEASE='-O3 -march=native -mtune=native'
-DCMAKE_CXX_FLAGS_RELEASE='-O3 -march=native -mtune=native'
-DLLAMA_CURL=OFF          # sin dependencia de libcurl
-DLLAMA_BUILD_TESTS=OFF
```

`-march=native` hace que GCC emita código exacto para esta CPU; combinado con el LTO
cruza los límites entre el runtime de ggml y los kernels de CPU.

### Verificación del binario

```bash
objdump -d bin/llama-cli | grep -c zmm   # debe ser 0 — sin AVX-512
objdump -d bin/llama-cli | grep -oE '\bymm[0-9]+' | sort -u   # hay ymm0..ymm13
```

**ymm presente = AVX2/FMA activos. zmm = 0 = nada de AVX-512 inexistente.**

## Contenido

```
bin/llama-cli      # chat en terminal
bin/llama-server   # servidor HTTP compatible con la API de OpenAI
bin/llama-bench    # benchmark
ollama-dist/       # ollama compilado (CLI + runner + libs ggml)
scripts/build.sh   # reproduce el build de llama.cpp desde cero
scripts/install.sh # instala los binarios de llama.cpp en ~/.local/bin
scripts/verify.sh  # verifica que el binario es de esta CPU
docs/              # notas de rendimiento
```

## Uso

```bash
# Chat directo
./bin/llama-cli -m ~/models/Qwen3-1.7B-Q4_K_M.gguf \
  --jinja --chat-template-kwargs '{"enable_thinking":false}' \
  -p 'user
Escribe un poema sobre el mar
assistant
' -c 2048 -t 4

# Servidor web (API estilo OpenAI en http://localhost:8080)
./bin/llama-server -m ~/models/Qwen3-1.7B-Q4_K_M.gguf \
  --jinja --chat-template-kwargs '{"enable_thinking":false}' \
  -c 4096 -t 4 --port 8080

# Benchmark
./bin/llama-bench -m ~/models/modelo.gguf -p 128 -n 32 -t 4
```

### El flag `--chat-template-kwargs` no es opcional en Qwen3

Los modelos Qwen3 tienen *thinking mode* activado por defecto: sin ese flag el modelo
imprime un bloque `[Start thinking]` y razona en inglés antes de responder, y con
`llama-cli -p` (sin `--jinja`) ese razonamiento se cuela en la salida. Con
`{"enable_thinking":false}` responde directo.

## Rendimiento medido

Medido en esta máquina, 4 hilos, promediado por `llama-bench`:

| Modelo | Tamaño | pp128 | tg32 (generación) |
|---|---|---|---|
| Qwen3-1.7B Q4_K_M | 1.03 GiB | 36.0 t/s | **11.4 t/s** |
| Qwen3-4B-Instruct-2507 Q4_K_M | 2.32 GiB | 5.5 t/s | **0.33 t/s** |

El salto de 1.7B a 4B multiplica el tiempo por respuesta ×35. La CPU, no la RAM, es el
cuello de botella: los 2.32 GiB del 4B caben sin problema en los 11 GiB disponibles, pero
la generación cae de 11.4 a 0.33 t/s porque falta ancho de banda de cómputo.

**Recomendación: 1B–2B Q4.** Hay 401 GB libres en disco, así que puedes tener varios
modelos; la restricción es la CPU, no el almacenamiento.

## Modelos recomendados

| Modelo | Tamaño | Generación | Notas |
|---|---|---|---|
| `unsloth/Qwen3-1.7B-GGUF` → `Qwen3-1.7B-Q4_K_M.gguf` | 1.11 GB | 11.4 t/s | El más usable de esta CPU |
| `bartowski/Llama-3.2-3B-Instruct-GGUF` → Q4_K_M | 2.02 GB | ~4 t/s | Más capaz, ya lento |
| `unsloth/Qwen3-1.7B-GGUF` → Q6_K | ~1.6 GB | ~7 t/s | Mejor calidad, sigue usable |

Descargas que **no** funcionan aquí, por ser MoE de 35B (21–37 GB):
`InternScience/Agents-A1-Q4_K_M-GGUF`, `InternScience/Agents-A1-Q8_0-GGUF`.
No es un problema de RAM — es que no existe versión pequeña del 35B que rinda aquí.

## Requisitos para reconstruir

Sin dependencias fuera del sistema salvo `cmake`, `gcc` (>= 11 por `-march=native`
confiable), `git` y `make`. No necesita `sudo`. Si quieres evitar `cmake` del sistema,
el build también funciona con un CMake portable:

```bash
curl -sSL -o /tmp/cmake.tar.gz \
  https://github.com/Kitware/CMake/releases/download/v4.0.3/cmake-4.0.3-linux-x86_64.tar.gz
tar xzf /tmp/cmake.tar.gz -C ~/.local/opt
export PATH="$HOME/.local/opt/cmake-4.0.3-linux-x86_64/bin:$PATH"
./scripts/build.sh
```

## Licencia

Los binarios de llama.cpp y de ollama están bajo la **MIT License**, igual que este
README y los scripts:

- llama.cpp — <https://github.com/ggml-org/llama.cpp/blob/master/LICENSE>
- ollama — <https://github.com/ollama/ollama/blob/main/LICENSE>

Los archivos `*LICENSE*` dentro de `bin/` y `ollama-dist/` son las licencias
originales de ggml, httplib y sus vendors, que se incluyen en el repo. Los modelos GGUF
tienen licencias propias, independientes de este repo.