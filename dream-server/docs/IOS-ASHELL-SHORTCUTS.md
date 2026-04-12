# iOS a-Shell + Apple Shortcuts

Last updated: 2026-04-11

## Goal

Use Dream Server on iOS as:

- a local CLI in `a-Shell`
- an intent router for Apple Shortcuts
- a stable shell contract that can later swap in a local wasm LLM backend

## Install on iPhone

Inside `a-Shell`:

```sh
sh ./install.sh
sh ./dream-mobile.sh status
```

By default, `sh ./install.sh` also downloads `Qwen3-0.6B-Q4_0.gguf` into `data/models/mobile/`.
If you want to skip the model download on a specific run:

```sh
sh ./install.sh --no-model-download
```

## Quick tests

```sh
sh ./dream-mobile.sh intent "abrir calculadora"
sh ./dream-mobile.sh intent "abrir safari no github"
sh ./dream-mobile.sh prompt "pesquisar clima em sao paulo"
sh ./dream-mobile.sh apps
```

## Output contract

The iOS preview returns JSON like this:

```json
{
  "ok": true,
  "engine": "rules",
  "mode": "ios-shortcuts-preview",
  "action": {
    "type": "open_app",
    "app_id": "calculator",
    "app_label": "Calculadora"
  },
  "spoken_response": "Abrindo Calculadora.",
  "confidence": 0.98
}
```

The stable action types today are:

- `open_app`
- `open_url`
- `run_shortcut`
- `compose_email`
- `reply`

For `compose_email`, the payload now also includes a ready-to-open `mailto_url`.

## Recommended Shortcut shape

Build the Shortcut around these steps:

1. Receive spoken or typed text.
2. Send that text into an `a-Shell` command that runs:

```sh
sh /path/to/DreamServer.git/dream-mobile.sh intent "abrir calculadora"
```

3. Parse the JSON result.
4. Route by `action.type`.

Suggested routing:

- `open_app`: use `action.app_id` to choose a fixed `Open App` action inside the Shortcut
- `open_url`: pass `action.url` into `Open URLs`
- `run_shortcut`: pass `action.shortcut_name` into `Run Shortcut`
- `compose_email`: the easiest route is `Open URLs` with `action.mailto_url`; that opens a ready draft without copy/paste. If you prefer, you can also use `action.to`, `action.subject`, and `action.body` in a Mail or `Send Email` action.
- `reply`: speak or display `spoken_response`

Example:

```sh
sh ./dream-mobile.sh intent "enviar email para ksgeladeira@gmail.com assunto teste texto oi, estou testando o Dream Server"
```

You can also ask Dream Server to draft the message for you from a topic:

```sh
sh ./dream-mobile.sh intent "enviar email para ksgeladeira@gmail.com sobre confirmar a reuniao de amanha as 14h"
```

That should return a `compose_email` action with:

- `to`
- `subject`
- `body`
- `mailto_url`

Today, this one-command email drafting path uses a stable local template generator so it works reliably inside the iPhone shell.

If you want the Qwen model itself to write the email body, use a Shortcut with two shell steps:

1. `Execute Command`:

```sh
cd /private/var/mobile/Containers/Data/Application/.../Documents/DreamServer.git
sh ./installers/mobile/ios-ashell-cli.sh prompt "Escreva um email curto e natural sobre confirmar a reuniao de amanha as 14h"
```

2. Feed that output into:

```sh
cd /private/var/mobile/Containers/Data/Application/.../Documents/DreamServer.git
sh ./installers/mobile/ios-ashell-cli.sh intent "enviar email para ksgeladeira@gmail.com assunto Confirmacao da reuniao texto $1"
```

That two-step Shortcut is more reliable than trying to invoke the local model from inside the `intent` router itself.

## One-tap Email Shortcut

If you do not want any manual copy/paste, build one Shortcut like this:

1. `Ask for Input`
   Voice or text. Example: `enviar email para ksgeladeira@gmail.com sobre confirmar a reuniao de amanha`
2. `Execute Command` in `a-Shell`
   Use:

```sh
cd /private/var/mobile/Containers/Data/Application/.../Documents/DreamServer.git
sh ./installers/mobile/ios-ashell-cli.sh intent "$1"
```

Pass the Shortcut input as the first argument.
3. `Get Dictionary from Input`
4. `If` `action.type` is `compose_email`
5. `Open URLs` with `action.mailto_url`

That flow is still a single tap for the user:

- speak or type the request
- Dream Server decides the action
- the Shortcut opens the ready email draft automatically

If you want automatic sending later, swap step 5 for a Mail / `Send Email` action that uses `action.to`, `action.subject`, and `action.body`.

## Why app IDs instead of app names

The Shortcut should branch on stable IDs like:

- `calculator`
- `camera`
- `clock`
- `notes`
- `safari`
- `settings`
- `files`
- `app_store`
- `music`
- `calendar`
- `reminders`
- `phone`
- `messages`
- `mail`

That is safer than relying on localized app names from shell output.

## Local runtime note

Today the iOS preview defaults to a local rule-based engine so the control loop is usable immediately.

The same CLI also reserves a slot for a future local wasm backend:

- expected runner: `wasm`
- expected binary path: `mobile-runtime/ios-ashell/bin/llama-cli.wasm`

There is now a host-side experimental builder for that runtime in:

- `dream-server/installers/mobile/build-ios-ashell-wasm-runtime.sh`

Current runtime notes, including the `wasi-sdk` exception-runtime blocker, live in:

- [`IOS-ASHELL-WASM-RUNTIME.md`](IOS-ASHELL-WASM-RUNTIME.md)

When that runtime exists, `sh ./dream-mobile.sh prompt "..."` can switch to local prompt inference without changing the Shortcut contract.
