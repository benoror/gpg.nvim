local M = {}

local function normalize_lines(lines)
  if #lines > 0 and lines[#lines] == "" then
    table.remove(lines, #lines)
  end
  return lines
end

local function read_lines(path)
  return normalize_lines(vim.fn.readfile(path))
end

local function lines_equal(a, b)
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end

function M.run()
  local file = vim.fn.getenv("GPG_TEST_FILE")
  local plaintext_file = vim.fn.getenv("GPG_TEST_PLAINTEXT_FILE")
  local expected_file = vim.fn.getenv("GPG_TEST_EXPECTED_FILE")
  local append_line = vim.fn.getenv("GPG_TEST_APPEND")

  if file == "" or plaintext_file == "" or expected_file == "" or append_line == "" then
    error("Missing GPG_TEST_* environment variables")
  end

  local original_system = vim.system
  local original_cmd = vim.cmd
  local gpg_connect_calls = 0
  local prime_calls = 0

  vim.system = function(cmd, opts)
    if type(cmd) == "table" and cmd[1] == "gpg-connect-agent" then
      gpg_connect_calls = gpg_connect_calls + 1
      return {
        wait = function()
          return { code = 0, stdout = "", stderr = "" }
        end,
      }
    end
    return original_system(cmd, opts)
  end

  vim.cmd = function(cmd)
    if type(cmd) == "string" and cmd:match("^silent! !gpg %-%-quiet %-%-list%-packets ") then
      prime_calls = prime_calls + 1
      return
    end
    return original_cmd(cmd)
  end

  vim.g.gpg_update_tty = nil
  vim.g.gpg_prime_agent = nil
  vim.cmd("edit " .. vim.fn.fnameescape(file))
  local content_lines = normalize_lines(vim.api.nvim_buf_get_lines(0, 0, -1, false))
  local expected_lines = read_lines(plaintext_file)
  if not lines_equal(content_lines, expected_lines) then
    error("Decrypted buffer does not match plaintext fixture")
  end

  vim.api.nvim_buf_set_lines(0, -1, -1, false, { append_line })
  vim.cmd("write")

  if gpg_connect_calls ~= 0 then
    error("Expected gpg_update_tty to be disabled by default")
  end

  local function assert_combo(update_tty, prime_agent, expect_update, expect_prime)
    local before_update = gpg_connect_calls
    local before_prime = prime_calls
    vim.g.gpg_update_tty = update_tty
    vim.g.gpg_prime_agent = prime_agent
    vim.cmd("edit " .. vim.fn.fnameescape(file))
    local update_delta = gpg_connect_calls - before_update
    local prime_delta = prime_calls - before_prime
    if expect_update and update_delta == 0 then
      error("Expected gpg_update_tty to trigger gpg-connect-agent")
    end
    if not expect_update and update_delta ~= 0 then
      error("Expected gpg_update_tty to be skipped")
    end
    if expect_prime and prime_delta == 0 then
      error("Expected gpg_prime_agent to trigger priming command")
    end
    if not expect_prime and prime_delta ~= 0 then
      error("Expected gpg_prime_agent to be skipped")
    end
  end

  assert_combo(false, false, false, false)
  assert_combo(true, false, true, false)
  assert_combo(false, true, false, true)
  assert_combo(true, true, true, true)

  vim.system = original_system
  vim.cmd = original_cmd
end

return M
