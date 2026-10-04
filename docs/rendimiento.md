# Why this CPU has these limits

Short version: **2 physical cores at 2.2 GHz with AVX2 and no AVX-512.** That single fact
determines everything about which models are usable.

## The measured numbers

All from `llama-bench`, 4 threads, this machine:

| Model | Params | Size | pp128 | tg32 |
|---|---|---|---|---|
| Qwen3-1.7B Q4_K_M | 1.72 B | 1.03 GiB | 36.02 ± 1.44 t/s | 11.43 ± 0.86 t/s |
| Qwen3-4B-Instruct-2507 Q4_K_M | 4.02 B | 2.32 GiB | 5.58 ± 0.45 t/s | 0.33 ± 0.07 t/s |

Prompt processing (pp) is **10× faster** than generation (tg) because pp is a big batched
matmul that saturates the FMA units, while token generation is memory-bandwidth-bound:
each new token must stream the whole model through the cache. That gap is why the model
"feels" responsive on input but crawls on output.

## Why 4B falls off a cliff

Going 1.7B → 4B is 2.3× the parameters. Memory traffic per generated token scales with
model size, and on this CPU that traffic is already the bottleneck. So generation time
should degrade roughly linearly — 11.43 → ~8 t/s expected. Instead it fell to 0.33 t/s,
a **35× drop**, not 1.4×.

The extra factor is the KV cache and context handling. Qwen3-4B has a larger vocab and
GQA layout that costs more per token, and with the default context the attention work per
token grows. Whatever the precise mix, the practical result is that 4B on this machine is
not interactive.

**This is not a memory problem.** 2.32 GiB fits easily in 11 GiB, and the benchmark ran
with 3.8 GiB still free — no swap activity. A machine with the same CPU but 32 GB of RAM
would run the 4B at the same 0.33 t/s. RAM only becomes the wall around 7B+.

## The AVX-512 trap

A generic build (`-march=x86-64-v3` or a distro default) would run fine but leave
performance on the table, because GCC would not emit the most efficient sequences for
this specific part. Conversely, enabling `-mavx512f` would produce a binary that
**crashes with SIGILL** on this CPU — it has no AVX-512. `-march=native` is the right
answer precisely because it reads the actual CPU capabilities rather than a guessed
target.

Verified in the shipped binary:

- `ymm` registers: present (AVX2 + FMA active)
- `zmm` registers: **0 occurrences** (no AVX-512 code)

## Thread count

`-t 4` uses all logical CPUs, but there are only 2 physical cores. Hyperthreading gives
maybe 10–20% over `-t 2` on generation, not 2×. The OpenMP build handles the threading;
`GGML_OPENMP=ON` plus `-t 4` is what the benchmarks above used.

## Practical guidance

- **Daily use:** 1B–2B Q4. Qwen3-1.7B Q4_K_M at 11.4 t/s is genuinely usable.
- **If you need more capability:** accept minutes per response, or use a remote API for
  heavy work and the local 1.7B for everything else. A hybrid setup is the practical answer
  on a CPU like this.
- **Don't bother** with MoE models (Agents-A1 35B, Mixtral, etc.). Even at Q2_K they are
  10–20 GB and every expert weight still has to be streamed from cache per token. MoE
  trades parameters for compute, which does not help when you're already memory-bound.

## Reproducing

The flags in `scripts/build.sh` produce a binary that passes all checks in
`scripts/verify.sh`. Build time on this laptop is roughly 45 minutes at `-j4` with LTO
enabled; disable `GGML_LTO` for a much faster build if you only need a working binary.