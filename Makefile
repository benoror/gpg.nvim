.PHONY: test-bash test-zsh test-nu test test-lazy test-packer

test-bash:
	bash scripts/test_bash.sh

test-zsh:
	zsh scripts/test_zsh.sh

test-nu:
	nu scripts/test_nu.nu

test-lazy:
	bash scripts/run_tests.sh tests/init_lazy.lua

test-packer:
	bash scripts/run_tests.sh tests/init_packer.lua
