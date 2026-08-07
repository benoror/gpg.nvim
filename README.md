<a href="https://dotfyle.com/plugins/benoror/gpg.nvim">
  <img src="https://dotfyle.com/plugins/benoror/gpg.nvim/shield" />
</a>

# gpg.nvim

Editing GPG encrypted files symmetrically in NeoVIM

![Demo](https://github.com/user-attachments/assets/2127cbe4-4199-4d0f-b9a3-b94798184cae)

## Install

### Manually

Copy [`plugin/gpg.lua`](https://github.com/benoror/gpg.nvim/blob/main/plugin/gpg.lua) file to your `~/.config/nvim/lua/plugins/` directory

### Using

#### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
-- ~/.config/nvim/lua/plugins/gpg.lua
{
   "benoror/gpg.nvim",
   ft = { "gpg", "asc", "pgp" },
}
```

#### vim.pack

```lua
-- ~/.config/nvim/init.lua
vim.pack.add({
   { "https://github.com/benoror/gpg.nvim" },
})
```

## Config

### Customize file extensions

```lua
vim.filetype.add({
	extension = {
		gpg = "gpg",
		asc = "asc",
	},
})

return {
	"benoror/gpg.nvim",
	ft = { "gpg", "asc", "pgp" },
}
```

Vía @Frestein [Frestein/dotfiles/dot_config/nvim/lua/plugins/extras/utils/gpg.lua](https://github.com/Frestein/dotfiles/blob/5169f2a5cae4bb992ea5c875a51f816a82e4582e/dot_config/nvim/lua/plugins/extras/utils/gpg.lua)

## Requirements

- `gpg` (GnuPG 2.1+ recommended for loopback pinentry)
- Optional: GUI pinentry (only needed if you disable loopback)

## Usage

All `*.gpg` files will be decrypted/encrypted transparently using `gpg` tools
(`--default-recipient-self` / asymmetric encrypt on write).

### Encrypting / decrypting a visual selection

This plugin intentionally stays focused on transparent whole-file editing for
`*.gpg` (and similar) buffers. Inline encrypt/decrypt of a visual selection —
including picking recipients from your keyring — is left to Neovim's built-in
external filter (`:!`) and `gpg`, so the plugin remains small and agnostic.

Select text in visual mode, then:

```vim
" Encrypt to yourself (ASCII-armored)
:'<,'>!gpg -ae --default-recipient-self

" Encrypt to a specific recipient
:'<,'>!gpg -ae -r alice@example.com

" Decrypt an armored PGP block
:'<,'>!gpg -qd
```

Optional keymaps:

```lua
vim.keymap.set("v", "<leader>ge", ":!gpg -ae --default-recipient-self<CR>", {
  desc = "GPG encrypt selection",
})
vim.keymap.set("v", "<leader>gd", ":!gpg -qd<CR>", {
  desc = "GPG decrypt selection",
})
```

For a recipient picker, list keys with `gpg --list-keys`, choose with
`vim.ui.select` / Telescope / fzf-lua, then run the same filter with one or more
`-r` flags. That UI is config-local and out of scope for this plugin.

### Passphrase prompting (default)

By default, decrypt uses `--pinentry-mode loopback` so Neovim owns the
passphrase prompt via `inputsecret()` when the agent does not already have the
key cached. This avoids `pinentry-curses` TTY contention (dropped key presses)
inside Neovim — see [issue #8](https://github.com/benoror/gpg.nvim/issues/8)
and [docs/pinentry.md](docs/pinentry.md) for the assessment, pros/cons, and
alternatives.

Loopback is on by default. To restore the legacy external pinentry path:

```lua
vim.g.gpg_pinentry_loopback = false
```

### Legacy GPG agent TTY handling

These opt-in knobs are legacy mitigations for the external pinentry path.
Prefer the default loopback behavior above.

Update the GPG agent startup TTY (equivalent to
`gpg-connect-agent updatestartuptty /bye`):

```lua
vim.g.gpg_update_tty = true
```

Optional "priming" step that runs `gpg --list-packets` before decrypting so
the passphrase may be cached by the agent:

```lua
vim.g.gpg_prime_agent = true
```

## Testing

Local smoke tests (headless Neovim, temp keyring):

```sh
make test-bash
make test-zsh
make test-nu
```

Plugin manager compatibility checks:

```sh
make test-lazy
make test-packer
```

Notes:
- The tests create a temporary `GNUPGHOME` and a throwaway key, so your user keyring is not touched.
- The tests also set isolated `XDG_*` paths and `NVIM_APPNAME` to a temp directory to avoid writing artifacts into your normal Neovim runtime.
- `tests/init_lazy.lua` and `tests/init_packer.lua` will clone their managers if missing (network required).

## Credits

### Based off

- From @nickali https://gist.github.com/nickali/89f3743e305db015d0f3ad4ffd325ccb
  - https://nali.org/wiki/tech/apps/neovim/#gpg-decrypting-and-encrypting-transparently-with-neovim
- Proposed first by @traut https://gist.github.com/traut/cd19ae2817ab13e0bade1f8a9995029f
  - https://www.reddit.com/r/nvim/comments/112a5bi/editing_gpg_encrypted_files_in_neovim/

### Inspired by

https://github.com/jamessan/vim-gnupg

## Further reading

- [Pinentry / passphrase notes](docs/pinentry.md) (issue #8 assessment, pros/cons)
- [Setup GPG on macOS](https://dev.to/zemse/setup-gpg-on-macos-2iib)
- [vim-gnupg#32](https://github.com/jamessan/vim-gnupg/issues/32) (related Neovim + pinentry TTY contention)
