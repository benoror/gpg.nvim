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

local function cmd_has(cmd, value)
  for _, part in ipairs(cmd) do
    if part == value then
      return true
    end
  end
  return false
end

local function with_gpg_mocks()
  local original_system = vim.system
  local original_cmd = vim.cmd
  local calls = {
    update_tty = 0,
    prime = 0,
    decrypt = 0,
    decrypt_loopback = 0,
    decrypt_legacy = 0,
    decrypt_passphrase_fd = 0,
  }

  vim.system = function(cmd, opts)
    if type(cmd) == "table" and cmd[1] == "gpg-connect-agent" then
      calls.update_tty = calls.update_tty + 1
      return {
        wait = function()
          return { code = 0, stdout = "", stderr = "" }
        end,
      }
    end
    if type(cmd) == "table" and cmd[1] == "gpg" and cmd_has(cmd, "--decrypt") then
      calls.decrypt = calls.decrypt + 1
      if cmd_has(cmd, "--pinentry-mode") and cmd_has(cmd, "loopback") then
        calls.decrypt_loopback = calls.decrypt_loopback + 1
      else
        calls.decrypt_legacy = calls.decrypt_legacy + 1
      end
      if cmd_has(cmd, "--passphrase-fd") then
        calls.decrypt_passphrase_fd = calls.decrypt_passphrase_fd + 1
      end
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
  -- Headless runs have no TTY; set a dummy so update_gpg_tty reaches gpg-connect-agent.
  if not vim.env.GPG_TTY or vim.env.GPG_TTY == "" then
    vim.env.GPG_TTY = "/dev/tty"
  end
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

local function assert_loopback_default(file, plaintext_file, calls)
  vim.g.gpg_pinentry_loopback = nil
  local before = calls.decrypt_loopback
  assert_decrypted_matches(file, plaintext_file)
  if calls.decrypt_loopback <= before then
    error("Expected default decrypt to use --pinentry-mode loopback")
  end
  if calls.decrypt_passphrase_fd ~= 0 then
    error("Did not expect passphrase-fd for unprotected/cached key")
  end
end

local function assert_legacy_opt_out(file, plaintext_file, calls)
  vim.g.gpg_pinentry_loopback = false
  local before_legacy = calls.decrypt_legacy
  local before_loopback = calls.decrypt_loopback
  assert_decrypted_matches(file, plaintext_file)
  if calls.decrypt_legacy <= before_legacy then
    error("Expected gpg_pinentry_loopback=false to use legacy decrypt")
  end
  if calls.decrypt_loopback ~= before_loopback then
    error("Did not expect loopback decrypt when opted out")
  end
  vim.g.gpg_pinentry_loopback = nil
end

local function assert_passphrase_retry(file, plaintext_file)
  local original_system = vim.system
  local original_inputsecret = vim.fn.inputsecret
  local attempts = 0
  local prompted = false

  vim.g.gpg_pinentry_loopback = true
  vim.fn.inputsecret = function()
    prompted = true
    return "test-passphrase"
  end

  vim.system = function(cmd, opts)
    if type(cmd) == "table" and cmd[1] == "gpg" and cmd_has(cmd, "--decrypt") then
      attempts = attempts + 1
      if attempts == 1 then
        if not (cmd_has(cmd, "--pinentry-mode") and cmd_has(cmd, "loopback")) then
          error("First decrypt attempt should use loopback")
        end
        if cmd_has(cmd, "--passphrase-fd") then
          error("First decrypt attempt should not use passphrase-fd")
        end
        return {
          wait = function()
            return {
              code = 2,
              stdout = "",
              stderr = "gpg: Sorry, we are in batchmode - can't get input",
            }
          end,
        }
      end

      if not cmd_has(cmd, "--passphrase-fd") then
        error("Retry should use --passphrase-fd")
      end
      if opts == nil or type(opts.stdin) ~= "string" or not opts.stdin:find("test-passphrase", 1, true) then
        error("Retry should pass passphrase on stdin")
      end
      if not cmd_has(cmd, file) then
        error("Retry should decrypt the on-disk file path")
      end

      -- Fall through to real decrypt with empty passphrase key after consuming fd.
      return original_system({
        "gpg",
        "--batch",
        "--yes",
        "--pinentry-mode",
        "loopback",
        "--decrypt",
        "--",
        file,
      }, {})
    end
    return original_system(cmd, opts)
  end

  local ok, err = pcall(assert_decrypted_matches, file, plaintext_file)
  vim.system = original_system
  vim.fn.inputsecret = original_inputsecret
  vim.g.gpg_pinentry_loopback = nil

  if not ok then
    error(err)
  end
  if not prompted then
    error("Expected inputsecret prompt when loopback decrypt needs a passphrase")
  end
  if attempts ~= 2 then
    error("Expected exactly one retry after passphrase prompt, got " .. tostring(attempts))
  end
end

local function assert_probe_wait_timeout(file, plaintext_file, configured, expected)
  local original_system = vim.system
  local seen = {}

  vim.g.gpg_pinentry_loopback = nil
  vim.g.gpg_probe_timeout = configured
  vim.system = function(cmd, opts)
    local obj = original_system(cmd, opts)
    if type(cmd) == "table" and cmd[1] == "gpg" and cmd_has(cmd, "--decrypt") and not cmd_has(cmd, "--passphrase-fd") then
      local orig_wait = obj.wait
      function obj:wait(timeout)
        table.insert(seen, timeout)
        return orig_wait(self, timeout)
      end
    end
    return obj
  end

  local ok, err = pcall(assert_decrypted_matches, file, plaintext_file)
  vim.system = original_system
  vim.g.gpg_probe_timeout = nil

  if not ok then
    error(err)
  end
  if #seen == 0 then
    error("Expected probe to call wait()")
  end
  if seen[1] ~= expected then
    error("Expected probe wait timeout " .. tostring(expected) .. ", got " .. tostring(seen[1]))
  end
end

local function assert_probe_timeout_hint(file)
  local original_system = vim.system
  local original_inputsecret = vim.fn.inputsecret
  local original_notify = vim.notify
  local wait_timeout
  local prompted = false
  local notices = {}

  vim.g.gpg_pinentry_loopback = true
  vim.g.gpg_probe_timeout = 50
  vim.notify = function(msg)
    table.insert(notices, msg)
  end
  vim.fn.inputsecret = function()
    prompted = true
    return "should-not-be-used"
  end
  vim.system = function(cmd, opts)
    if type(cmd) == "table" and cmd[1] == "gpg" and cmd_has(cmd, "--decrypt") then
      if cmd_has(cmd, "--passphrase-fd") then
        error("Should not retry passphrase-fd after probe timeout")
      end
      return {
        wait = function(_, timeout)
          wait_timeout = timeout
          return {
            code = 124,
            signal = 9,
            stdout = "",
            stderr = "",
          }
        end,
      }
    end
    return original_system(cmd, opts)
  end

  local ok, err = pcall(open_file, file)
  vim.system = original_system
  vim.fn.inputsecret = original_inputsecret
  vim.notify = original_notify
  vim.g.gpg_pinentry_loopback = nil
  vim.g.gpg_probe_timeout = nil

  if not ok then
    error(err)
  end
  if prompted then
    error("Did not expect inputsecret after probe timeout")
  end
  if wait_timeout ~= 50 then
    error("Expected probe wait timeout 50, got " .. tostring(wait_timeout))
  end
  local found = false
  for _, msg in ipairs(notices) do
    if
      type(msg) == "string"
      and msg:find("timed out", 1, true)
      and msg:find("use-keyboxd", 1, true)
    then
      found = true
      break
    end
  end
  if not found then
    error("Expected timeout notify to mention GnuPG/keyboxd")
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
  vim.g.gpg_pinentry_loopback = nil
  assert_loopback_default(file, plaintext_file, calls)
  assert_legacy_opt_out(file, plaintext_file, calls)

  if calls.update_tty ~= 0 then
    error("Expected gpg_update_tty to be disabled by default")
  end

  -- Content checks that need the unmodified fixture must run before write.
  restore_mocks()
  assert_passphrase_retry(file, plaintext_file)
  assert_probe_timeout_hint(file)
  assert_probe_wait_timeout(file, plaintext_file, nil, 30000)
  assert_probe_wait_timeout(file, plaintext_file, 12345, 12345)
  assert_probe_wait_timeout(file, plaintext_file, false, nil)
  assert_probe_wait_timeout(file, plaintext_file, 0, nil)

  calls, restore_mocks = with_gpg_mocks()
  vim.g.gpg_update_tty = nil
  vim.g.gpg_prime_agent = nil
  vim.g.gpg_pinentry_loopback = nil
  assert_decrypted_matches(file, plaintext_file)
  append_and_write(append_line)

  assert_combo(file, false, false, false, false, calls)
  assert_combo(file, true, false, true, false, calls)
  assert_combo(file, false, true, false, true, calls)
  assert_combo(file, true, true, true, true, calls)

  restore_mocks()

  local decrypted_lines = normalize_lines(vim.fn.readfile(expected_file))
  if #decrypted_lines == 0 then
    error("Expected decrypted output fixture to be non-empty")
  end
end

return M
