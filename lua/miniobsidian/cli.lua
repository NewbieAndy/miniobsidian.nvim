local M = {}

local PROTOCOL = "obs-cli/v2"
local VAULT_CONTRACT = "vault-contract/v1"

local state = {
  status = "disabled",
  reason = "CLI integration is disabled",
  error = nil,
  capabilities = {},
  operations = {},
  cli_version = nil,
  protocol_version = nil,
  vault_contract = nil,
  checked_at = nil,
}

local generation = 0

local function config()
  local core = require("miniobsidian")
  return core.config.cli or {}
end

local function adapter_error(code, message, details)
  return {
    code = code,
    message = message,
    retryable = false,
    details = details or {},
  }
end

local function notify(callback, result, err)
  if not callback then
    return
  end
  vim.schedule(function()
    callback(result, err)
  end)
end

local function reset(next_status, reason, err)
  state = {
    status = next_status,
    reason = reason,
    error = err,
    capabilities = {},
    operations = {},
    cli_version = nil,
    protocol_version = nil,
    vault_contract = nil,
    checked_at = os.time(),
  }
end

local function decode_envelope(stdout)
  local ok, envelope = pcall(vim.json.decode, stdout or "")
  if not ok or type(envelope) ~= "table" then
    return nil, adapter_error("CLI_INVALID_JSON", "obs-cli returned invalid JSON")
  end
  if envelope.protocol_version ~= PROTOCOL then
    return nil,
      adapter_error("CLI_PROTOCOL_INCOMPATIBLE", "obs-cli protocol is incompatible", {
        expected = PROTOCOL,
        actual = envelope.protocol_version,
      })
  end
  if envelope.ok == false then
    if type(envelope.error) == "table" and type(envelope.error.code) == "string" then
      return nil, envelope.error
    end
    return nil, adapter_error("CLI_EXEC_FAILED", "obs-cli returned an error without a stable error envelope")
  end
  if envelope.ok ~= true then
    return nil, adapter_error("CLI_INVALID_JSON", "obs-cli JSON envelope is missing ok=true")
  end
  return envelope, nil
end

local function command_argv(args)
  local cli_config = config()
  local argv = { cli_config.command }
  for _, value in ipairs(args) do
    argv[#argv + 1] = value
  end
  return argv
end

local function validate_args(args)
  if type(args) ~= "table" or #args == 0 then
    return false, adapter_error("CLI_INVALID_ARGUMENT", "CLI args must be a non-empty argv table")
  end
  for index, value in ipairs(args) do
    if type(value) ~= "string" or value == "" then
      return false,
        adapter_error("CLI_INVALID_ARGUMENT", "CLI argv values must be non-empty strings", {
          index = index,
        })
    end
  end
  return true, nil
end

---@return table
function M.state()
  return vim.deepcopy(state)
end

---@param operation string
---@return boolean
function M.available(operation)
  return state.status == "ready" and state.operations[operation] ~= nil
end

---@param callback? fun(result: table|nil, err: table|nil)
---@return boolean started
function M.refresh(callback)
  generation = generation + 1
  local current_generation = generation
  local cli_config = config()

  if cli_config.enabled == false then
    reset("disabled", "CLI integration is disabled")
    notify(callback, M.state(), nil)
    return false
  end
  if vim.fn.executable(cli_config.command) ~= 1 then
    local err = adapter_error("CLI_UNAVAILABLE", "obs-cli executable was not found", {
      command = cli_config.command,
    })
    reset("unavailable", err.message, err)
    notify(callback, M.state(), nil)
    return false
  end

  reset("checking", "Checking obs-cli capabilities")
  vim.system(command_argv({ "capabilities", "--output", "json" }), {
    text = true,
    timeout = cli_config.timeout_ms,
  }, function(process)
    if current_generation ~= generation then
      return
    end
    if process.code ~= 0 then
      local code = process.code == 124 and "CLI_TIMEOUT" or "CLI_EXEC_FAILED"
      local err = adapter_error(code, "obs-cli capability check failed", {
        exit_code = process.code,
        signal = process.signal,
        stderr = process.stderr or "",
      })
      reset("error", err.message, err)
      notify(callback, M.state(), nil)
      return
    end

    local envelope, err = decode_envelope(process.stdout)
    if not envelope then
      local status = err.code == "CLI_PROTOCOL_INCOMPATIBLE" and "incompatible" or "error"
      reset(status, err.message, err)
      notify(callback, M.state(), nil)
      return
    end
    if envelope.operation ~= "capabilities.get" or type(envelope.data) ~= "table" then
      err = adapter_error("CLI_INVALID_JSON", "obs-cli capability envelope has an invalid operation or data")
      reset("error", err.message, err)
      notify(callback, M.state(), nil)
      return
    end

    local supports_protocol = false
    for _, version in ipairs(envelope.data.protocol_versions or {}) do
      if version == PROTOCOL then
        supports_protocol = true
        break
      end
    end
    if not supports_protocol then
      err = adapter_error("CLI_PROTOCOL_INCOMPATIBLE", "obs-cli does not advertise obs-cli/v2")
      reset("incompatible", err.message, err)
      notify(callback, M.state(), nil)
      return
    end

    local contract = envelope.data.vault_contract
    if type(contract) ~= "table" or contract.implemented ~= VAULT_CONTRACT then
      err = adapter_error("CLI_VAULT_CONTRACT_INCOMPATIBLE", "obs-cli Vault contract is incompatible", {
        expected = VAULT_CONTRACT,
        actual = type(contract) == "table" and contract.implemented or nil,
      })
      reset("incompatible", err.message, err)
      notify(callback, M.state(), nil)
      return
    end

    local operations = {}
    for _, operation in ipairs(envelope.data.operations or {}) do
      if type(operation) == "table" and type(operation.name) == "string" then
        operations[operation.name] = vim.deepcopy(operation)
      end
    end
    state = {
      status = "ready",
      reason = "obs-cli capabilities are available",
      error = nil,
      capabilities = vim.deepcopy(envelope.data),
      operations = operations,
      cli_version = envelope.data.cli_version,
      protocol_version = envelope.protocol_version,
      vault_contract = contract.implemented,
      checked_at = os.time(),
    }
    notify(callback, M.state(), nil)
  end)
  return true
end

---@param config_override? table
function M.setup(config_override)
  if config_override then
    require("miniobsidian").config.cli = config_override
  end
  M.refresh()
end

---@param args string[]
---@param opts? {operation?: string, mutating?: boolean, timeout_ms?: number}
---@param callback? fun(result: table|nil, err: table|nil)
---@return boolean started
function M.call(args, opts, callback)
  opts = opts or {}
  local valid, err = validate_args(args)
  if not valid then
    notify(callback, nil, err)
    return false
  end
  if state.status ~= "ready" then
    notify(
      callback,
      nil,
      state.error or adapter_error("CLI_UNAVAILABLE", "obs-cli capabilities are not ready", { status = state.status })
    )
    return false
  end
  if opts.mutating and not opts.operation then
    notify(callback, nil, adapter_error("CLI_INVALID_ARGUMENT", "mutating calls require an operation name"))
    return false
  end
  if opts.operation and not M.available(opts.operation) then
    notify(
      callback,
      nil,
      adapter_error("CAPABILITY_UNSUPPORTED", "required obs-cli capability is unavailable", {
        operation = opts.operation,
      })
    )
    return false
  end

  local cli_config = config()
  vim.system(command_argv(args), {
    text = true,
    timeout = opts.timeout_ms or cli_config.timeout_ms,
  }, function(process)
    if process.code ~= 0 then
      local code = process.code == 124 and "CLI_TIMEOUT" or "CLI_EXEC_FAILED"
      notify(
        callback,
        nil,
        adapter_error(code, "obs-cli invocation failed", {
          exit_code = process.code,
          signal = process.signal,
          stderr = process.stderr or "",
        })
      )
      return
    end
    local envelope, decode_err = decode_envelope(process.stdout)
    if not envelope then
      notify(callback, nil, decode_err)
      return
    end
    notify(callback, envelope, nil)
  end)
  return true
end

---@return {level: "ok"|"info"|"warn", message: string}
function M.health_status()
  local cli_config = config()
  if cli_config.enabled == false or state.status == "disabled" then
    return { level = "info", message = "obs-cli integration disabled (optional)" }
  end
  if state.status == "ready" then
    return {
      level = "ok",
      message = ("obs-cli %s ready (%d capabilities)"):format(
        state.cli_version or "unknown",
        vim.tbl_count(state.operations)
      ),
    }
  end
  local level = cli_config.enabled == true and "warn" or "info"
  return {
    level = level,
    message = ("obs-cli optional integration: %s (%s)"):format(state.reason, state.status),
  }
end

return M
