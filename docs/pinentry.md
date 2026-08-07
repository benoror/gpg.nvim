# Pinentry / passphrase handling

Tracking context for [issue #8](https://github.com/benoror/gpg.nvim/issues/8):
key presses randomly dropped during `pinentry-curses` prompts under Neovim.

## Assessment

### Symptom

When decrypting a `.gpg` buffer, `pinentry-curses` may appear on the terminal,
but keystrokes are intermittently ignored (or split between Neovim and
pinentry). The same class of bug exists in
[jamessan/vim-gnupg#32](https://github.com/jamessan/vim-gnupg/issues/32).

### Root cause

Neovim and `pinentry-curses` contend for the same TTY:

1. The plugin runs `gpg` through `vim.system()` (no dedicated PTY for pinentry).
2. When the agent needs a passphrase, it launches pinentry against `$GPG_TTY`.
3. Neovim continues owning terminal input, so keystrokes are raced.

This is not a flaky passphrase; it is an input-routing conflict.

### Why earlier mitigations were incomplete

| Approach | What it does | Limitation |
| --- | --- | --- |
| `gpg_update_tty` (`updatestartuptty`) | Points the agent at the current TTY | Does not stop Neovim from also reading keys |
| `gpg_prime_agent` (`gpg --list-packets`) | Tries to cache the passphrase first | Priming still needs pinentry when locked; contention remains |
| Pre-unlock outside Neovim | Agent already has the key | Works, but is a manual workaround |
| GUI pinentry | Avoids terminal pinentry | Not available / undesirable on SSH / headless |

## Chosen fix (plugin default)

Use GPG **loopback pinentry mode** and, when needed, prompt inside Neovim with
`vim.fn.inputsecret()`, then pass the passphrase via `--passphrase-fd`.

Decrypt flow:

1. `gpg --batch --pinentry-mode loopback --decrypt` with ciphertext on stdin  
   (succeeds when the agent already has the key, or the key has no passphrase).
2. If gpg reports that it needs a passphrase, prompt with `inputsecret`.
3. Retry with `--passphrase-fd 0` and decrypt the on-disk `.gpg` file path  
   (stdin carries only the passphrase).

Opt out (legacy pinentry UI path):

```lua
vim.g.gpg_pinentry_loopback = false
```

### Pros

- Pinentry UI agnostic: no dependency on `pinentry-curses`, GTK, macOS, etc.
- Works over SSH / headless / tmux without TTY fights.
- Minimal surface area: still shells out to `gpg`, no PTY multiplexer.
- Keeps ciphertext-on-stdin for the common cached-agent case.
- Aligns with the long-term direction discussed for vim-gnupg (loopback + job control).

### Cons

- Changes UX for users who preferred a GUI pinentry popup (they get Neovim's secret prompt instead, unless they opt out).
- Requires GnuPG 2.1+ loopback support (`--pinentry-mode loopback`).
- Wrong passphrase surfaces as a decrypt error; reopen the buffer to retry.
- Passphrase is briefly held in Lua/Neovim memory and passed on a pipe (same general class of tradeoff as any loopback/`--passphrase-fd` integration).

## Alternatives not chosen

### PTY-wrapped pinentry

Spawn `gpg`/pinentry on a dedicated PTY (`pty = true` / `termopen`) and park
Neovim input until it finishes.

- More terminal/UI coupling, floating-term orchestration, and platform edge cases.
- Fights the goal of keeping this plugin small and generic.

### User-only configuration

Setting `allow-loopback-pinentry` alone (or switching pinentry programs) does
**not** fix the plugin path by itself: ciphertext already occupies stdin in
`vim.system()`, so the plugin must own passphrase acquisition when loopback is
used interactively.

## Legacy optional knobs

Still available when loopback is disabled, or as extra agent hygiene:

```lua
vim.g.gpg_update_tty = true
vim.g.gpg_prime_agent = true
```

Prefer leaving loopback enabled (default) instead of relying on these.
