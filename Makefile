NVIM ?= nvim
MINI_COMMIT := 1345d191bb3da9c7b0e977f4387c5761f9bff68d

.PHONY: test test-file deps

test: deps
	$(NVIM) --headless --noplugin -u tests/minimal_init.lua -c "lua MiniTest.run()"

# make test-file FILE=tests/test_m1.lua
test-file: deps
	$(NVIM) --headless --noplugin -u tests/minimal_init.lua -c "lua MiniTest.run_file('$(FILE)')"

deps: deps/mini.nvim

deps/mini.nvim:
	git clone --quiet --filter=blob:none https://github.com/nvim-mini/mini.nvim deps/mini.nvim
	git -C deps/mini.nvim checkout --quiet $(MINI_COMMIT)
