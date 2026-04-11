# iOS a-Shell WASM Runtime

Last updated: 2026-04-11

## Goal

Use the same `dream-mobile.sh` CLI on iOS with a real local `Qwen3-0.6B` backend by placing a `llama-cli.wasm` runtime at:

```text
mobile-runtime/ios-ashell/bin/llama-cli.wasm
```

## What exists now

The repo now includes a host-side experimental builder:

```sh
bash dream-server/installers/mobile/build-ios-ashell-wasm-runtime.sh
```

That builder:

- clones a pinned `llama.cpp` checkout
- generates a tiny prompt-only WASI runner
- drives the official `wasi-sdk` Docker image
- copies the output into the exact path that the iOS preview already checks

## Current blocker

Today the build reaches almost all of `llama.cpp`, but the final link still fails on the published `wasi-sdk` image because the required C++ exception runtime symbols are missing for `wasm32-wasi-threads`.

The missing symbols in the current path include:

- `__cxa_allocate_exception`
- `__cxa_throw`
- `__wasm_lpad_context`
- `_Unwind_CallPersonality`

This is why the iPhone can already:

- download `Qwen3-0.6B-Q4_0.gguf`
- report `Downloaded:true`
- keep a stable `prompt` / `chat` shell contract

but still cannot run local Qwen inference in `a-Shell` yet.

## What success looks like

Once the runtime links cleanly, the iOS flow does not need a new interface. The existing commands can switch over:

```sh
sh ./dream-mobile.sh status
sh ./dream-mobile.sh prompt "oi"
sh ./dream-mobile.sh chat
```

And `status` should move from:

```text
Engine:    rules
Wasm ready:false
```

to:

```text
Engine:    wasm
Wasm ready:true
```

## Practical note

This builder is meant to run on a desktop host with Docker, not inside `a-Shell`.
