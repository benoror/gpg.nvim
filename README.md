<a href="https://dotfyle.com/plugins/benoror/gpg.nvim">
  <img src="https://dotfyle.com/plugins/benoror/gpg.nvim/shield" />
</a>

# gpg.nvim

Editing GPG encrypted files symmetrically in NeoVIM

![Demo](https://github.com/user-attachments/assets/2127cbe4-4199-4d0f-b9a3-b94798184cae)

## Install

### Manually

Copy [`plugin/gpg.lua`](https://github.com/benoror/gpg.nvim/blob/main/plugin/gpg.lua) file to your `~/.config/nvim/lua/plugins/` directory

### Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
-- ~/.config/nvim/lua/plugins/gpg.lua
{
   "benoror/gpg.nvim",
}
```

## Requirements

- `gpg`
- Optional: `pinentry-mac`

## Usage

All `*.gpg` files will be symmetrically decrypted/encrypted transparently using `gpg` tools

## Testing

Local smoke tests (headless Neovim, temp keyring):

```sh
bash scripts/test_bash.sh
zsh scripts/test_zsh.sh
nu scripts/test_nu.nu
```

Plugin manager compatibility checks:

```sh
bash scripts/run_tests.sh tests/init_lazy.lua
bash scripts/run_tests.sh tests/init_packer.lua
```

Notes:
- The tests create a temporary `GNUPGHOME` and a throwaway key, so your user keyring is not touched.
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

- [Setup GPG on macOS](https://dev.to/zemse/setup-gpg-on-macos-2iib)
