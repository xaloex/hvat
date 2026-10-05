-- injector.lua — тихий MITM для исполнителя (вставлять ПЕРЕД запуском скрипта)
-- 1. Ловит момент отправки (syn.request / http_request / request / game:HttpGet)
-- 2. Пишет Url/Headers/Body в файл, добавляет НЕВИДИМУЮ метку (свой заголовок X-Tap)
-- 3. Отправляет ДАЛЬШЕ НА НАСТОЯЩИЙ сервер (не фейк), ответ отдает скрипту как был
-- Сигнатура X-Pulse-Sig не ломается: она покрывает только Method/path/TS/Nonce/HWID/Env/Body,
-- наш заголовок X-Tap в подпись не входит, сервер его игнорирует, скрипт его не видит.
local TAG = "tap-" .. tostring(math.random(100000, 999999))

local function dump(v)
  local ok, hs = pcall(function() return game:GetService("HttpService"):JSONEncode(v) end)
  if ok then return tostring(hs):sub(1, 3000) end
  return tostring(v):sub(1, 3000)
end

local DUMP_DIR = "server-dump"
local DUMP_LOG = DUMP_DIR .. "/tap.log"

pcall(function()
  if makefolder and isfolder and not isfolder(DUMP_DIR) then makefolder(DUMP_DIR) end
end)

local dumpN = 0
local function saveDump(kind, text)
  pcall(function()
    if not writefile then return end
    dumpN = dumpN + 1
    writefile(DUMP_DIR .. "/" .. kind .. "_" .. tostring(os.time()) .. "_" .. tostring(dumpN) .. ".txt", tostring(text or ""))
  end)
end

local function log(line)
  pcall(function()
    if writefile then
      local old = isfile and isfile(DUMP_LOG) and readfile(DUMP_LOG) or ""
      writefile(DUMP_LOG, old .. line .. "\n")
    end
  end)
  print(line)
end

local function isWebhook(url)
  local u = string.lower(url)
  return u:find("discord") or u:find("webhook") or u:find("telegram")
    or u:find("hooks%.slack") or u:find("guilded")
end

local function wrap(tag, orig)
  return function(p)
    local url = ""
    if type(p) == "table" then url = tostring(p.Url or p.url or "") end
    local snap = url:find("admin/snapshot") and true or false
    local hook = isWebhook(url)
    -- ловим ВСЕ: снапшот и любые вебхуки полностью, остальное коротко
    log("[TAP] " .. tag .. " " .. tostring(type(p) == "table" and (p.Method or p.method) or "") .. " Url=" .. url)
    if snap or hook then
      log("[TAP] headers=" .. dump(type(p) == "table" and p.Headers or nil))
      log("[TAP] body=" .. tostring(type(p) == "table" and p.Body or p or ""):sub(1, 3000))
      if snap then saveDump("req", url .. "\n" .. dump(p.Headers) .. "\n" .. tostring(p.Body or "")) end
      if hook then saveDump("webhook", url .. "\n" .. dump(p.Headers) .. "\n" .. tostring(p.Body or "")) end
      if type(p) == "table" then
        p.Headers = p.Headers or {}
        p.Headers["X-Tap"] = TAG
      end
    end
    local res = orig(p)
    if snap or hook then
      log("[TAP] resp status=" .. tostring(res and (res.StatusCode or res.status)))
      log("[TAP] resp body=" .. tostring(res and res.Body):sub(1, 3000))
      saveDump("resp", tostring(res and (res.StatusCode or res.status)) .. "\n" .. tostring(res and res.Body))
    end
    return res -- скрипту отдаем оригинал, он ничего не замечает
  end
end

if hookfunction then
  if syn and syn.request then
    local old = syn.request
    syn.request = wrap("syn.request", old)
  end
  if http_request then
    local old = http_request
    http_request = wrap("http_request", old)
  end
  if request then
    local old = request
    request = wrap("request", old)
  end
  -- game:HttpGet для иконок/шрифтов
  if game and game.HttpGet then
    local old = game.HttpGet
    game.HttpGet = function(self, url, ...)
      log("[TAP] game:HttpGet Url=" .. tostring(url))
      return old(self, url, ...)
    end
  end
  log("[TAP] armed, tag=" .. TAG .. " dir=" .. DUMP_DIR)
else
  log("[TAP] no hookfunction (sandbox mode), idle")
end
