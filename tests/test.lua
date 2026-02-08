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

  vim.cmd("edit " .. vim.fn.fnameescape(file))
  local content_lines = normalize_lines(vim.api.nvim_buf_get_lines(0, 0, -1, false))
  local expected_lines = read_lines(plaintext_file)
  if not lines_equal(content_lines, expected_lines) then
    error("Decrypted buffer does not match plaintext fixture")
  end

  vim.api.nvim_buf_set_lines(0, -1, -1, false, { append_line })
  vim.cmd("write")
end

return M
