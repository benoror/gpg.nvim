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

- `gpg`
- Optional: `pinentry-mac`

## Usage

All `*.gpg` files will be symmetrically decrypted/encrypted transparently using `gpg` tools

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
