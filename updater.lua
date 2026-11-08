-- updater.lua — модуль обновления файлов из ПРИВАТНОГО GitHub-репозитория.
-- Используется вкладкой «Обновление» панели ME-Control.
--
-- Требует интернет-карту и Personal Access Token в файле /home/mecontrol.token
--   (fine-grained token, Repository access: только этот репозиторий,
--    Permissions: Contents = Read-only).
--
-- Логика повторяет getcode.lua (атомарная запись через *.tmp + rename),
-- но оформлена как модуль:
--
--   local ok, msg = require("updater").run(function(text)
--       -- text — очередной шаг/строка для журнала
--   end)
--
-- run() возвращает true при полном успехе либо false и текст ошибки.

local component = require("component")
local filesystem = require("filesystem")
local computer = require("computer")

-- Библиотеку internet подключаем необязательно: без неё модуль должен
-- загружаться (чтобы панель вообще запустилась), а run() вернёт ошибку.
local okNet, internet = pcall(require, "internet")
if not okNet then internet = nil end

local updater = {}

-- ================= НАСТРОЙКИ =================
local USER = "lixynhay"
local REPO = "me-control"
local BRANCH = "main"
local TARGET_DIR = "/home/"
local TOKEN_FILE = "/home/mecontrol.token"
local REQUEST_RETRIES = 3
local RETRY_DELAY = 1
local READ_TIMEOUT = 60
-- =============================================

local apiBase = "https://api.github.com/repos/" .. USER .. "/" .. REPO .. "/contents/"

-- ---------- Утилиты ----------

local function readToken()
    if not filesystem.exists(TOKEN_FILE) then return nil end
    local f = io.open(TOKEN_FILE, "r")
    if not f then return nil end
    local t = f:read("*l")
    f:close()
    if t then t = t:match("^%s*(.-)%s*$") end
    if not t or t == "" then return nil end
    return t
end

local function isSafePath(path)
    if type(path) ~= "string" or path == "" then return false end
    if path:find("..", 1, true) then return false end
    if path:sub(1, 1) == "/" or path:sub(1, 1) == "\\" then return false end
    if path:find(":", 1, true) then return false end
    if path:find("\\", 1, true) then return false end
    return true
end

local function mkdirp(path)
    if not path or path == "" then return true end
    local acc = ""
    for part in path:gmatch("[^/]+") do
        acc = acc .. "/" .. part
        if not filesystem.exists(acc) then
            local ok = filesystem.makeDirectory(acc)
            if not ok then return false, acc end
        end
    end
    return true
end

local function formatSize(bytes)
    if bytes < 1024 then return bytes .. " B"
    elseif bytes < 1024 * 1024 then return string.format("%.1f KB", bytes / 1024)
    else return string.format("%.1f MB", bytes / (1024 * 1024)) end
end

-- Установленная на компьютере версия (/home/version.txt)
local function getLocalVersion()
    local f = io.open("/home/version.txt", "r")
    if not f then return "не установлено" end
    local v = f:read("*a")
    f:close()
    if not v then return "не установлено" end
    v = v:gsub("%s+", "")
    if v == "" then return "не установлено" end
    return v
end

local function urlFor(filePath)
    return apiBase .. filePath .. "?ref=" .. BRANCH
end

-- GET с авторизацией. Возвращает response-итератор или nil, err
local function requestAuth(url, headers)
    local lastErr = "неизвестная ошибка"
    for attempt = 1, REQUEST_RETRIES do
        local ok, response = pcall(internet.request, url, nil, headers)
        if not ok or not response then
            ok, response = pcall(internet.request, url, "", headers)
        end
        if ok and response then return response end
        lastErr = tostring(response)
        if attempt < REQUEST_RETRIES then os.sleep(RETRY_DELAY) end
    end
    return nil, lastErr
end

local function readAll(response)
    local chunks = {}
    local ok, err = pcall(function()
        for chunk in response do chunks[#chunks + 1] = chunk end
    end)
    if not ok then return nil, tostring(err) end
    return table.concat(chunks)
end

local function looksLikeApiError(text)
    if not text then return false end
    return text:match('^%s*{%s*"message"') ~= nil
end

-- Скачивание одного файла с атомарной записью (*.tmp -> rename)
local function downloadFile(filePath, headers)
    local targetPath = TARGET_DIR .. filePath
    local tmpPath = targetPath .. ".tmp"

    local dir = filesystem.path(targetPath)
    if dir ~= "" then
        local dOk, dBad = mkdirp(dir)
        if not dOk then return false, "не удалось создать каталог: " .. tostring(dBad) end
    end

    local resp, reqErr = requestAuth(urlFor(filePath), headers)
    if not resp then return false, "нет связи (" .. tostring(reqErr) .. ")" end

    local file = io.open(tmpPath, "wb")
    if not file then return false, "не удалось открыть файл на запись" end

    local bytes = 0
    local startedAt = computer.uptime()
    local ok, err = pcall(function()
        local first = true
        for chunk in resp do
            if first then
                first = false
                if looksLikeApiError(chunk) or chunk:find("Not Found", 1, true) then
                    error("GitHub API: " .. chunk:sub(1, 100))
                end
            end
            file:write(chunk)
            bytes = bytes + #chunk
            if computer.uptime() - startedAt > READ_TIMEOUT then
                error("timeout: превышен лимит " .. READ_TIMEOUT .. " с")
            end
        end
    end)

    file:close()

    if not ok then
        filesystem.remove(tmpPath)
        return false, tostring(err)
    end

    if filesystem.exists(targetPath) then filesystem.remove(targetPath) end
    local renamed, renameErr = filesystem.rename(tmpPath, targetPath)
    if not renamed then
        filesystem.remove(tmpPath)
        return false, "не удалось переименовать: " .. tostring(renameErr)
    end

    return true, bytes
end

-- ================== ПУБЛИЧНОЕ API ==================
-- progressCallback(text) вызывается на каждом шаге.
-- Возвращает true при полном успехе, иначе false и текст ошибки.
function updater.run(progressCallback)
    local progress = progressCallback or function() end

    if not component.isAvailable("internet") then
        return false, "Интернет-карта не найдена"
    end
    if not internet then
        return false, "Библиотека internet недоступна"
    end

    local token = readToken()
    if not token then
        return false, "Не найден токен: " .. TOKEN_FILE
    end

    local headers = {
        ["Authorization"] = "Bearer " .. token,
        ["Accept"] = "application/vnd.github.raw",
        ["User-Agent"] = "oc-me-control",
    }

    local oldVersion = getLocalVersion()

    -- ---- 1. Манифест ----
    progress("Загрузка manifest.txt")
    local mResp, mErr = requestAuth(urlFor("manifest.txt"), headers)
    if not mResp then
        return false, "Нет связи с GitHub: " .. tostring(mErr)
    end
    local manifestData, mReadErr = readAll(mResp)
    if not manifestData then
        return false, "Не удалось прочитать manifest.txt: " .. tostring(mReadErr)
    end
    if looksLikeApiError(manifestData) or manifestData:find("Not Found", 1, true) then
        return false, "manifest.txt недоступен (проверьте токен)"
    end
    if manifestData:match("^%s*$") then
        return false, "manifest.txt пуст"
    end

    -- ---- 2. Парсинг ----
    local filesToDownload, seen = {}, {}
    local skipped = 0
    for line in manifestData:gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" and not line:match("^#") then
            if not isSafePath(line) then
                skipped = skipped + 1
                progress("[ПРОПУСК] Небезопасный путь: " .. line)
            elseif seen[line] then
                skipped = skipped + 1
            else
                seen[line] = true
                filesToDownload[#filesToDownload + 1] = line
            end
        end
    end

    if #filesToDownload == 0 then
        return false, "В manifest.txt нет файлов для загрузки"
    end

    local totalFiles = #filesToDownload
    progress("Файлов к загрузке: " .. totalFiles ..
        (skipped > 0 and (" (пропущено: " .. skipped .. ")") or ""))

    -- ---- 3. Скачивание ----
    local successCount, failed, totalBytes = 0, 0, 0
    local startTime = computer.uptime()

    for i, filePath in ipairs(filesToDownload) do
        progress(string.format("[%d/%d] Скачивание %s...", i, totalFiles, filePath))
        local ok, info = downloadFile(filePath, headers)
        if ok then
            successCount = successCount + 1
            totalBytes = totalBytes + info
            progress(string.format("[%d/%d] OK: %s | %s", i, totalFiles, filePath, formatSize(info)))
        else
            failed = failed + 1
            progress(string.format("[%d/%d] ОШИБКА: %s | %s", i, totalFiles, filePath, tostring(info)))
        end
    end

    -- ---- 4. Итоги ----
    local timeTaken = computer.uptime() - startTime
    local newVersion = getLocalVersion()

    progress(string.format("Общий размер: %s | Время: %.2f с", formatSize(totalBytes), timeTaken))
    local verMsg
    if newVersion == oldVersion then
        verMsg = "Текущая версия актуальна: " .. newVersion
    elseif oldVersion == "не установлено" then
        verMsg = "Установлена версия: " .. newVersion
    else
        verMsg = "ОБНОВЛЕНИЕ: " .. oldVersion .. " -> " .. newVersion
    end
    progress(verMsg)

    if successCount > 0 and failed == 0 then
        return true, verMsg
    end
    return false, "Часть файлов не обновлена (ошибок: " .. failed .. ")"
end

return updater
