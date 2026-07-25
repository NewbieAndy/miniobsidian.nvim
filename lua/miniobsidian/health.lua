local M = {}

local function get_health()
  if vim.health then
    return vim.health
  end
  local ok, h = pcall(require, "health")
  if ok then
    return h
  end
  return nil
end

local function ver_ge(a, b)
  if a.major ~= b.major then
    return a.major > b.major
  end
  if a.minor ~= b.minor then
    return a.minor > b.minor
  end
  return a.patch >= b.patch
end

local function uname()
  local uv = vim.uv or vim.loop
  if not uv or not uv.os_uname then
    return nil
  end
  return uv.os_uname()
end

---@param core table
---@return {level: "ok"|"info"|"warn"|"error", message: string}[]
function M.vault_status(core)
  local result = {}
  local parent = core.config.vaults_parent
  local active = core.config.vault_path

  if not parent or parent == "" then
    if core.config.auto_discover == false then
      return { { level = "error", message = "vaults_parent 为空且 auto_discover 已关闭" } }
    end
    result[#result + 1] = { level = "ok", message = "Vault 来源: Obsidian 自动发现" }
    if active and active ~= "" and vim.fn.isdirectory(active) == 1 then
      result[#result + 1] = { level = "ok", message = "active vault_path: " .. active }
    else
      result[#result + 1] = {
        level = "error",
        message = "自动发现未得到有效的 active vault_path；请先在 Obsidian 中打开 Vault",
      }
    end
    return result
  end

  parent = vim.fn.expand(parent)
  if vim.fn.isdirectory(parent) ~= 1 then
    return { { level = "error", message = "vaults_parent 目录不存在: " .. parent } }
  end
  result[#result + 1] = { level = "ok", message = "vaults_parent: " .. parent }

  local vault = require("miniobsidian.vault")
  vault.refresh_vaults()
  local vaults = vault.list_vaults(parent)
  if #vaults == 0 then
    result[#result + 1] = { level = "error", message = "未找到含 .obsidian/ 的有效 Vault" }
    return result
  end
  result[#result + 1] = { level = "ok", message = ("vaults found: %d"):format(#vaults) }

  if active and active ~= "" and vim.fn.isdirectory(active) == 1 then
    result[#result + 1] = { level = "ok", message = "active vault_path: " .. active }
  else
    result[#result + 1] = { level = "warn", message = "active vault_path 无效；setup() 可能未成功" }
  end
  return result
end

function M.check()
  local h = get_health()
  if not h then
    return
  end

  h.start("miniobsidian.nvim")

  local required = { major = 0, minor = 10, patch = 4 }
  local current = vim.version()
  if ver_ge(current, required) then
    h.ok(("Neovim %d.%d.%d"):format(current.major, current.minor, current.patch))
  else
    h.error(
      ("Neovim %d.%d.%d (required >= %d.%d.%d)"):format(
        current.major,
        current.minor,
        current.patch,
        required.major,
        required.minor,
        required.patch
      )
    )
  end

  local ok_snacks, snacks = pcall(require, "snacks")
  if ok_snacks and snacks and snacks.picker then
    h.ok("snacks.nvim found")
  else
    h.warn("snacks.nvim not found (quick switch/search disabled)")
  end

  if vim.fn.executable("rg") == 1 then
    h.ok("ripgrep (rg) found")
  else
    h.warn("ripgrep (rg) not found (full-text search disabled)")
  end

  local sys = uname()
  local is_macos = sys and sys.sysname == "Darwin"
  if is_macos then
    if vim.fn.executable("osascript") == 1 then
      h.ok("osascript found (image paste enabled)")
    else
      h.warn("osascript not found (image paste may not work)")
    end
  else
    h.info("non-macOS: image paste is disabled")
  end

  local ok_blink = pcall(require, "blink.cmp")
  if ok_blink then
    h.ok("blink.cmp found (completion enabled)")
  else
    h.info("blink.cmp not found (completion disabled)")
  end

  local core_ok, core = pcall(require, "miniobsidian")
  if not core_ok or not core or not core.config then
    h.warn("miniobsidian core not loaded")
    return
  end

  for _, message in ipairs(core.validate_config(core.config)) do
    h.error("config: " .. message)
  end
  for _, item in ipairs(M.vault_status(core)) do
    h[item.level](item.message)
  end

  local cli_ok, cli = pcall(require, "miniobsidian.cli")
  if cli_ok then
    local item = cli.health_status()
    h[item.level](item.message)
  else
    h.info("obs-cli integration unavailable (optional)")
  end
end

return M
