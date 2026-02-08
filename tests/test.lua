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

local function get_env_or_error(name)
  local value = vim.fn.getenv(name)
  if value == "" then
    error("Missing " .. name .. " environment variable")
  end
  return value
end

local function open_file(path)
  vim.cmd("edit " .. vim.fn.fnameescape(path))
end

local function assert_decrypted_matches(path, plaintext_file)
  open_file(path)
  local content_lines = normalize_lines(vim.api.nvim_buf_get_lines(0, 0, -1, false))
  local expected_lines = read_lines(plaintext_file)
  if not lines_equal(content_lines, expected_lines) then
    error("Decrypted buffer does not match plaintext fixture")
  end
end

local function append_and_write(line)
  vim.api.nvim_buf_set_lines(0, -1, -1, false, { line })
  vim.cmd "write"
end

local function with_gpg_mocks()
  local original_system = vim.system
  local original_cmd = vim.cmd
  local calls = { update_tty = 0, prime = 0 }

  vim.system = function(cmd, opts)
    if type(cmd) == "table" and cmd[1] == "gpg-connect-agent" then
      calls.update_tty = calls.update_tty + 1
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
      calls.prime = calls.prime + 1
      return
    end
    return original_cmd(cmd)
  end

  local function restore()
    vim.system = original_system
    vim.cmd = original_cmd
  end

  return calls, restore
end

local function assert_combo(file, update_tty, prime_agent, expect_update, expect_prime, calls)
  local before_update = calls.update_tty
  local before_prime = calls.prime
  vim.g.gpg_update_tty = update_tty
  vim.g.gpg_prime_agent = prime_agent
  open_file(file)
  local update_delta = calls.update_tty - before_update
  local prime_delta = calls.prime - before_prime
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

function M.run()
  local file = get_env_or_error "GPG_TEST_FILE"
  local plaintext_file = get_env_or_error "GPG_TEST_PLAINTEXT_FILE"
  local expected_file = get_env_or_error "GPG_TEST_EXPECTED_FILE"
  local append_line = get_env_or_error "GPG_TEST_APPEND"

  local calls, restore_mocks = with_gpg_mocks()

  vim.g.gpg_update_tty = nil
  vim.g.gpg_prime_agent = nil
  assert_decrypted_matches(file, plaintext_file)
  append_and_write(append_line)

  if calls.update_tty ~= 0 then
    error("Expected gpg_update_tty to be disabled by default")
  end

  assert_combo(file, false, false, false, false, calls)
  assert_combo(file, true, false, true, false, calls)
  assert_combo(file, false, true, false, true, calls)
  assert_combo(file, true, true, true, true, calls)

  local decrypted_lines = normalize_lines(vim.fn.readfile(expected_file))
  if #decrypted_lines == 0 then
    error("Expected decrypted output fixture to be non-empty")
  end

  restore_mocks()
end

return M
