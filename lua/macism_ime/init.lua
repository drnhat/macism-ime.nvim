-- macism-ime.nvim: lua/macism_ime/init.lua
-- Tự động chuyển bộ gõ trên macOS (dùng macism) theo mode của Neovim.
--
--   Khởi động      : lưu input hiện tại, về ABC
--   Typing mode    : Insert / Replace / Select / Terminal -> trả lại input phù hợp (xem "Chọn input")
--   Rời typing     : nhớ input đang dùng, về ABC
--   / ?  và :%s/   : trả lại input phù hợp; rời dòng lệnh thì về ABC
--   Thoát / Ctrl-Z : trả lại input trước khi mở nvim
--
-- Chọn input khi vào Insert (ưu tiên từ trên xuống, mục nào tắt/không có thì xuống mục sau):
--   1. detect          : dòng quanh con trỏ có chữ Việt có dấu        (mặc định: tắt)
--   2. filetype_input  : input ép cho từng filetype                   (mặc định: trống)
--   3. nhớ theo buffer : input dùng lần trước trong buffer này        (scope = "buffer")
--   4. nhớ toàn cục    : input dùng lần trước ở bất kỳ đâu
--
-- Dùng:   require("macism_ime").setup()   -- hoặc require("macism_ime").setup({ wait = 100 })
-- Lệnh:   :MacismImeToggle   :MacismImeInfo
--
-- Yêu cầu: macism (brew install laishulu/homebrew/macism), Neovim >= 0.10 (có fallback cho bản cũ hơn).

local M = {}

local ABC = "com.apple.keylayout.ABC"

local defaults = {
  normal = ABC,           -- input cho Normal / Visual / ":"
  remember = true,        -- true: nhớ input của lần Insert trước
                          -- false: luôn dùng input lúc mở nvim (hoặc insert_default)
  scope = "global",       -- "global": nhớ chung cho mọi buffer
                          -- "buffer": nhớ riêng từng buffer (code tiếng Anh, ghi chú tiếng Việt...)
  insert_default = nil,   -- input cho lần Insert đầu tiên nếu lúc mở nvim đang là ABC, ví dụ "com.codetay.inputmethod.XKey"
  filetype_input = {},    -- ép input theo filetype, ví dụ { markdown = "com.codetay.inputmethod.XKey", lua = "com.apple.keylayout.ABC" }
  detect = {
    enable = false,       -- true: thấy chữ Việt có dấu trên dòng con trỏ thì dùng input bên dưới
    input = nil,          -- BẮT BUỘC khi enable: input dùng khi thấy chữ Việt, ví dụ "com.codetay.inputmethod.XKey"
    -- Vim regex (không phải Lua pattern): chữ cái tiếng Việt có dấu, không khớp Latin-1 khác
    pattern = [==[[àáâãèéêìíòóôõùúýÀÁÂÃÈÉÊÌÍÒÓÔÕÙÚÝăĂđĐĩĨũŨơƠưƯ\u1ea0-\u1ef9]]==],
  },
  macism = nil,           -- đường dẫn tới macism; nil = tự tìm trong PATH, rồi /opt/homebrew/bin, /usr/local/bin
  wait = nil,             -- ms chờ khi chuyển sang bộ gõ CJKV như XKey; nil = mặc định macism (150ms)
  timeout = 1500,         -- ms; macism treo quá lâu thì bỏ qua thay vì đơ nvim
  terminal = true,        -- true: terminal mode (:terminal) cũng được coi là typing mode
  focus_sync = true,      -- quay lại cửa sổ nvim (FocusGained) mà không ở Insert -> ép về ABC
  exclude_filetypes = {}, -- filetype không bao giờ bật bộ gõ tiếng Việt, ví dụ { "gitrebase" }
  -- Lệnh ":" cần trả lại input; Lua pattern kiểm tra trên dòng lệnh đang gõ.
  cmdline_patterns = {
    "^%s*[%%%d%.%$,;+%-]*s[/#]",   -- :s/  :%s/  :1,5s/  :.,$s/
    "^%s*'[<>%a],'[<>%a]s[/#]",    -- :'<,'>s/  :'a,'bs/
    -- "^%s*[%%%d%.%$,;+%-]*[gv]/", -- bỏ comment nếu muốn cả :g/ và :v/
  },
  debug = false,          -- true: ghi log vào ~/.local/state/nvim/ime.log
}

local opts = vim.tbl_extend("force", {}, defaults)

local state = {
  enabled = true,
  initialized = false,
  original = nil,       -- input trước khi mở nvim
  last_insert = nil,    -- input dùng cho Insert lần trước (toàn cục)
  cmd_tried = false,    -- đã thử trả lại input trong lần mở dòng lệnh này
  cmd_restored = false, -- dòng lệnh hiện tại đang dùng input "tiếng Việt"
  left = false,         -- đã trả input gốc khi thoát
  vi_regex = nil,       -- regex đã biên dịch của detect.pattern
  detect_broken = false,
  bin = nil,            -- đường dẫn macism đã tìm được
}

---------------------------------------------------------------------------
-- Tiện ích
---------------------------------------------------------------------------

local function log(...)
  if not opts.debug then return end
  local parts = {}
  for i = 1, select("#", ...) do
    parts[#parts + 1] = tostring((select(i, ...)))
  end
  local f = io.open(vim.fn.stdpath("state") .. "/ime.log", "a")
  if f then
    f:write(os.date("%H:%M:%S "), table.concat(parts, " "), "\n")
    f:close()
  end
end

-- Tìm macism: đường dẫn do người dùng đặt -> PATH -> các thư mục Homebrew quen thuộc.
-- (nvim chạy từ app GUI như Tridactyl/Alfred thường không có /opt/homebrew/bin trong PATH)
local function find_macism()
  if opts.macism and opts.macism ~= "" then
    local p = vim.fn.expand(opts.macism)
    if vim.fn.executable(p) == 1 then return p end
    return nil
  end
  local p = vim.fn.exepath("macism")
  if p ~= "" then return p end
  for _, dir in ipairs({ "/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin" }) do
    local c = dir .. "/macism"
    if vim.fn.executable(c) == 1 then return c end
  end
  return nil
end

-- Chạy macism, trả về stdout (đã trim) hoặc nil nếu lỗi / quá timeout.
local function run(args)
  if vim.system then
    local ok, res = pcall(function()
      return vim.system(args, { text = true }):wait(opts.timeout)
    end)
    if not ok or not res or res.code ~= 0 then return nil end
    return vim.trim(res.stdout or "")
  end
  local out = vim.fn.system(args)
  if vim.v.shell_error ~= 0 then return nil end
  return vim.trim(out)
end

local function current()
  local id = run({ state.bin })
  if id == nil or id == "" then return nil end
  return id
end

local function switch(id)
  if not id or id == "" then return false end
  local cmd = { state.bin, id }
  if id == opts.normal then
    cmd[3] = "0" -- ABC không cần workaround của macism => đổi tức thì
  elseif opts.wait then
    cmd[3] = tostring(opts.wait)
  end
  local ok = run(cmd) ~= nil
  if not ok then
    vim.notify_once("macism_ime: macism không chuyển được sang " .. id, vim.log.levels.WARN)
  end
  log("switch", id, ok and "ok" or "FAILED")
  return ok
end

-- Mode mà bạn gõ chữ: Insert, Replace, Select, (Terminal).
-- Chú ý: "niI" (Insert + Ctrl-O) bắt đầu bằng "n" nên được coi là Normal.
local function is_typing(mode)
  local c = mode:sub(1, 1)
  if c == "i" or c == "R" then return true end
  if c == "s" or c == "S" or c == "\19" then return true end
  if c == "t" then return opts.terminal end
  return false
end

local function excluded()
  return vim.tbl_contains(opts.exclude_filetypes, vim.bo.filetype)
end

---------------------------------------------------------------------------
-- Chọn input cho Insert / dòng lệnh tìm kiếm
---------------------------------------------------------------------------

-- Dòng quanh con trỏ có chữ Việt có dấu? (nếu dòng trống thì xét dòng phía trên, hợp với `o`)
local function detect_input()
  local d = opts.detect
  if not d.enable or state.detect_broken then return nil end
  if not d.input then
    state.detect_broken = true
    vim.notify_once("macism_ime: detect.enable = true nhưng chưa đặt detect.input", vim.log.levels.WARN)
    return nil
  end

  if not state.vi_regex then
    local ok, re = pcall(vim.regex, d.pattern)
    if not ok then
      state.detect_broken = true
      vim.notify_once("macism_ime: detect.pattern không hợp lệ: " .. tostring(re), vim.log.levels.WARN)
      return nil
    end
    state.vi_regex = re
  end

  local line = vim.api.nvim_get_current_line()
  if not line:find("%S") then
    local row = vim.api.nvim_win_get_cursor(0)[1]
    if row > 1 then
      line = vim.api.nvim_buf_get_lines(0, row - 2, row - 1, false)[1] or ""
    end
  end
  if state.vi_regex:match_str(line) then return d.input end
  return nil
end

local function insert_target()
  local id = detect_input()
  if id then return id end

  id = opts.filetype_input[vim.bo.filetype]
  if id then return id end

  if opts.scope == "buffer" and vim.b.ime_last then
    return vim.b.ime_last
  end
  return state.last_insert
end

local function remember_input(id)
  state.last_insert = id
  if opts.scope == "buffer" then vim.b.ime_last = id end
end

---------------------------------------------------------------------------
-- Hành vi theo mode
---------------------------------------------------------------------------

local function enter_typing()
  if excluded() then return end
  local id = insert_target()
  if id and id ~= opts.normal then
    log("enter typing ->", id)
    switch(id)
  end
end

local function leave_typing()
  if opts.remember and not excluded() then
    local cur = current()
    if cur then
      remember_input(cur)
      log("leave typing, remember", cur)
      if cur ~= opts.normal then switch(opts.normal) end
      return
    end
  end
  switch(opts.normal)
end

local function on_mode_change()
  if not state.enabled then return end
  local ev = vim.v.event
  local was, now = is_typing(ev.old_mode), is_typing(ev.new_mode)
  if was == now then return end -- ví dụ i -> ic (popup completion): không làm gì
  if now then enter_typing() else leave_typing() end
end

-- Ép về ABC khi không ở typing mode (dùng cho FocusGained / VimResume / bật lại)
local function sync()
  if not state.enabled then return end
  if is_typing(vim.api.nvim_get_mode().mode) or state.cmd_restored then return end
  local cur = current()
  if cur and cur ~= opts.normal then
    log("sync -> normal")
    switch(opts.normal)
  end
end

---------------------------------------------------------------------------
-- Dòng lệnh: / ? và :%s/
---------------------------------------------------------------------------

local function restore_for_cmdline()
  if state.cmd_tried then return end
  state.cmd_tried = true -- chỉ thử một lần mỗi lần mở dòng lệnh
  if excluded() then return end
  local id = insert_target()
  if id and id ~= opts.normal then
    state.cmd_restored = switch(id)
  end
end

local function on_cmdline_enter()
  if not state.enabled then return end
  state.cmd_tried, state.cmd_restored = false, false
  local t = vim.fn.getcmdtype()
  if t == "/" or t == "?" then restore_for_cmdline() end
end

local function on_cmdline_changed()
  if not state.enabled or state.cmd_tried or vim.fn.getcmdtype() ~= ":" then return end
  local line = vim.fn.getcmdline()
  for _, p in ipairs(opts.cmdline_patterns) do
    if line:match(p) then
      restore_for_cmdline()
      return
    end
  end
end

local function on_cmdline_leave()
  if state.cmd_restored then
    state.cmd_restored = false
    switch(opts.normal)
  end
  state.cmd_tried = false
end

---------------------------------------------------------------------------
-- Khởi động / thoát
---------------------------------------------------------------------------

local function init()
  if state.initialized then return end -- setup() gọi lại không được ghi đè input gốc
  state.initialized = true
  local cur = current()
  state.original = cur
  if cur and cur ~= opts.normal then
    state.last_insert = cur
    switch(opts.normal)
  else
    state.last_insert = opts.insert_default or cur
  end
  log("init original =", cur, "last_insert =", state.last_insert)
  -- nvim +startinsert, v.v.
  if is_typing(vim.api.nvim_get_mode().mode) then enter_typing() end
end

local function restore_original()
  if state.left then return end
  state.left = true
  if state.original then
    log("restore original", state.original)
    switch(state.original)
  end
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

function M.setup(user)
  if vim.fn.has("mac") == 0 then return end -- dotfiles dùng chung với Linux vẫn an toàn
  user = user or {}
  opts = vim.tbl_extend("force", {}, defaults, user)
  opts.detect = vim.tbl_extend("force", {}, defaults.detect, user.detect or {}) -- gộp từng khóa của detect
  state.vi_regex, state.detect_broken = nil, false

  state.bin = find_macism()
  if not state.bin then
    vim.notify_once("macism_ime: không tìm thấy macism (PATH, /opt/homebrew/bin, /usr/local/bin). Cài: brew install laishulu/homebrew/macism, hoặc đặt setup({ macism = \"/đường/dẫn/macism\" })", vim.log.levels.WARN)
    return
  end

  local group = vim.api.nvim_create_augroup("MacismIme", { clear = true })
  local function au(event, fn, extra)
    vim.api.nvim_create_autocmd(event, vim.tbl_extend("force", { group = group, callback = fn }, extra or {}))
  end

  if vim.v.vim_did_enter == 1 then init() else au("VimEnter", init) end

  au("ModeChanged", on_mode_change, { pattern = "*:*" })
  au("CmdlineEnter", on_cmdline_enter)
  au("CmdlineChanged", on_cmdline_changed)
  au("CmdlineLeave", on_cmdline_leave)

  if opts.focus_sync then
    au("FocusGained", sync) -- trong tmux cần: set -g focus-events on
  end

  au("VimLeavePre", restore_original)

  -- Ctrl-Z / :suspend (event có từ Neovim 0.10; pcall để bản cũ không lỗi)
  pcall(vim.api.nvim_create_autocmd, "VimSuspend", {
    group = group,
    callback = function()
      if state.enabled and state.original then switch(state.original) end
    end,
  })
  pcall(vim.api.nvim_create_autocmd, "VimResume", { group = group, callback = sync })

  vim.api.nvim_create_user_command("MacismImeToggle", function()
    state.enabled = not state.enabled
    if state.enabled then
      sync()
    elseif state.original then
      switch(state.original)
    end
    vim.notify("IME auto-switch: " .. (state.enabled and "ON" or "OFF"))
  end, { desc = "Bật/tắt tự động chuyển bộ gõ" })

  vim.api.nvim_create_user_command("MacismImeInfo", function()
    vim.notify(table.concat({
      "enabled:     " .. tostring(state.enabled),
      "macism:      " .. tostring(state.bin),
      "scope:       " .. tostring(opts.scope),
      "original:    " .. tostring(state.original),
      "last_insert: " .. tostring(state.last_insert),
      "buffer:      " .. tostring(vim.b.ime_last),
      "target:      " .. tostring(insert_target()),
      "current:     " .. tostring(current()),
    }, "\n"))
  end, { desc = "Xem trạng thái IME" })
end

return M
