local serialization = require("serialization")
local filesystem = require("filesystem")

local db = {}
local DB_PATH = "/home/database.dat"
local DB_LOG_PATH = "/home/database.log"
local data = nil

-- Диагностика повреждённых записей: пишем в отдельный лог, не ломая загрузку.
-- Любая ошибка записи игнорируется — аудит не должен мешать работе панели.
local function logWarning(message)
    local okT, t = pcall(os.time)
    local stamp = (okT and tonumber(t)) or 0
    local line = string.format("[%s] %s\n", tostring(stamp), tostring(message))
    pcall(function()
        local f = io.open(DB_LOG_PATH, "a")
        if f then
            f:write(line)
            f:close()
        end
    end)
end

-- Глобальные права по умолчанию. true = текущее фактическое поведение при
-- отсутствии ключа (nil трактуется как «разрешено»), но теперь состояние явное.
local DEFAULT_CONFIG = {
    allowUserWithdraw = true,
    allowUserDeposit = true,
    allowUserCraft = true,
}

local function defaultConfig()
    return {
        allowUserWithdraw = true,
        allowUserDeposit = true,
        allowUserCraft = true,
    }
end

-- ===== Иерархия ролей =====
-- Чем больше число, тем больше прав. Управлять можно только теми, кто НИЖЕ.
db.ROLE_LEVELS = {
    ["banned"]    = 0,
    ["guest"]     = 1,   -- только смотреть
    ["user"]      = 2,   -- брать / сдавать
    ["moderator"] = 3,   -- банить юзеров
    ["admin"]     = 4,   -- менять роли
    ["techadmin"] = 5,   -- всемогущий
}

-- Порядок для переключения роли в интерфейсе (от младшей к старшей)
db.ROLE_ORDER = { "guest", "user", "moderator", "admin" }

-- Уровень роли игрока (0, если игрока нет или роль неизвестна)
function db.getRoleLevel(name)
    local p = db.getPlayer(name)
    if not p then return -1 end
    return db.ROLE_LEVELS[p.role] or 0
end

-- Проверка иерархии: может ли actorName управлять targetName.
-- Себя менять нельзя (кроме отдельных операций вроде смены собственных флагов).
function db.hasPermission(actorName, targetName, action)
    action = action or "manage"
    if not actorName or not targetName then
        return false, "Не указан игрок"
    end
    if actorName == targetName then
        return false, "Нельзя выполнить это действие над собой"
    end

    local actor = db.getPlayer(actorName)
    if not actor then return false, "Нет доступа: вы не зарегистрированы" end

    local actorLevel = db.ROLE_LEVELS[actor.role] or 0
    if actorLevel < 3 then
        return false, "Недостаточно прав для выполнения операции"
    end

    local target = db.getPlayer(targetName)
    if not target then return false, "Игрок не найден" end

    local targetLevel = db.ROLE_LEVELS[target.role] or 0

    -- Строго выше по уровню
    if actorLevel <= targetLevel then
        return false, "Недостаточно прав: цель не ниже вас по уровню"
    end

    -- Дополнительные ограничения по конкретному действию
    -- (ban уже покрыт общим guard'ом actorLevel < 3 выше).
    if action == "setRole" and actorLevel < 4 then
        return false, "Менять роли могут администраторы и выше"
    end
    if action == "setPermission" and actorLevel < 4 then
        return false, "Менять права могут администраторы и выше"
    end

    return true
end

-- Загрузка базы данных из файла
function db.load()
    -- Сбрасываем прежнее состояние: повторный load() должен корректно
    -- обрабатывать замену/повреждение database.dat, а не держать старые данные.
    data = nil

    -- Читаем основной файл; если его нет, пробуем недописанный *.tmp
    -- (после аварии он может быть единственным валидным источником).
    local function readFrom(path)
        if not filesystem.exists(path) then return nil end
        local file = io.open(path, "r")
        if not file then return nil end
        local content = file:read("*a")
        file:close()
        local ok, loaded = pcall(serialization.unserialize, content)
        if ok and type(loaded) == "table" then return loaded end
        return nil
    end

    -- Однократный бэкап исходного файла перед миграцией/восстановлением.
    -- Если .bak уже есть, не перезаписываем: он хранит состояние до первой миграции.
    local function backupOnce(sourcePath)
        local bakPath = DB_PATH .. ".bak"
        if filesystem.exists(bakPath) then return true end
        local src = io.open(sourcePath, "r")
        if not src then return false end
        local content = src:read("*a")
        src:close()
        local dst = io.open(bakPath, "w")
        if not dst then return false end
        local ok = pcall(function() dst:write(content) end)
        dst:close()
        return ok
    end

    local loaded = readFrom(DB_PATH)
    local loadedPath = DB_PATH
    if not loaded then
        loaded = readFrom(DB_PATH .. ".tmp")
        loadedPath = DB_PATH .. ".tmp"
    end

    local changed = false

    if loaded then
        data = loaded
        -- Восстановление из *.tmp всегда закрепляем в основном файле,
        -- иначе после следующей перезагрузки данные останутся только в .tmp.
        if loadedPath ~= DB_PATH then changed = true end
        if type(data.players) ~= "table" then
            data.players = {}
            changed = true
        end
        -- Миграция конфига: гарантируем все три ключа allowUser*.
        if type(data.config) ~= "table" then
            data.config = defaultConfig()
            changed = true
        else
            for key, value in pairs(DEFAULT_CONFIG) do
                if data.config[key] == nil then
                    data.config[key] = value
                    changed = true
                end
            end
        end
        if type(data.thresholds) ~= "table" then
            data.thresholds = {}
            changed = true
        end
        if type(data.logs) ~= "table" then
            data.logs = {}
            changed = true
        end
        local brokenPlayers = {}
        for name, p in pairs(data.players) do
            if type(p) ~= "table" then
                -- Битая запись (строка/число) не должна ронять загрузку всей БД.
                brokenPlayers[#brokenPlayers + 1] = name
            else
                if p.banReason == nil then p.banReason = ""; changed = true end
                if p.banExpires == nil then p.banExpires = 0; changed = true end
                -- Миграция: персональные права (появились в v1.7.0)
                if p.canWithdraw == nil then p.canWithdraw = true; changed = true end
                if p.canDeposit == nil then p.canDeposit = true; changed = true end
                if p.canCraft == nil then p.canCraft = true; changed = true end
                -- Миграция: статистика профиля (v1.7.1)
                if p.totalActions == nil then p.totalActions = 0; changed = true end
                if p.lastSeen == nil then p.lastSeen = 0; changed = true end
            end
        end
        for _, name in ipairs(brokenPlayers) do
            data.players[name] = nil
            changed = true
            logWarning("db.load: пропущена битая запись игрока: " .. tostring(name))
        end
        if changed then backupOnce(loadedPath) end
    end

    -- Если файла нет или он поврежден, создаем структуру по умолчанию
    if not data then
        -- Повреждённый файл сохраняем в .bak (однократно) — для разбора.
        if filesystem.exists(DB_PATH) then
            backupOnce(DB_PATH)
        elseif filesystem.exists(DB_PATH .. ".tmp") then
            backupOnce(DB_PATH .. ".tmp")
        end
        data = {
            players = {
                ["lixynhay"] = { role = "admin" }
            },
            config = defaultConfig(),
            thresholds = {},
            logs = {}
        }
        changed = true
    end

    -- Технический администратор: роль всегда techadmin, аккаунт создаётся при необходимости
    if data.players["lixynhay"] then
        local p = data.players["lixynhay"]
        if p.role ~= "techadmin" then p.role = "techadmin"; changed = true end
        if p.canWithdraw == nil then p.canWithdraw = true; changed = true end
        if p.canDeposit == nil then p.canDeposit = true; changed = true end
        if p.canCraft == nil then p.canCraft = true; changed = true end
        if p.totalActions == nil then p.totalActions = 0; changed = true end
        if p.lastSeen == nil then p.lastSeen = 0; changed = true end
    else
        data.players["lixynhay"] = {
            role = "techadmin",
            canWithdraw = true, canDeposit = true, canCraft = true,
            totalActions = 0, lastSeen = 0,
            banReason = "", banExpires = 0,
        }
        changed = true
    end

    -- Сохраняем только при изменениях (миграция/создание), чтобы не переписывать
    -- здоровую БД на каждом запуске.
    if changed then db.save() end
end

-- Сохранение базы данных в файл (атомарно: *.tmp -> rename)
-- Записываем во временный файл, затем атомарно заменяем основной. Так обрыв
-- питания/ошибка ФС в момент записи не оставит повреждённый database.dat.
function db.save()
    if not data then return false end
    local content = serialization.serialize(data)
    local tmpPath = DB_PATH .. ".tmp"
    local file = io.open(tmpPath, "w")
    if not file then
        return false, "Ошибка сохранения БД"
    end
    local ok, err = pcall(function() file:write(content) end)
    file:close()
    if not ok then
        filesystem.remove(tmpPath)
        return false, "Ошибка сохранения БД"
    end
    local renamed, renameErr = filesystem.rename(tmpPath, DB_PATH)
    if not renamed then
        -- rename мог не сработать из-за существующего database.dat. Не удаляем
        -- оригинал заранее: сначала пробуем copy поверх, затем remove + rename.
        local original = nil
        if filesystem.exists(DB_PATH) then
            local src = io.open(DB_PATH, "r")
            if src then
                original = src:read("*a")
                src:close()
            end
        end

        local copied = false
        if type(filesystem.copy) == "function" then
            local okCopy = filesystem.copy(tmpPath, DB_PATH)
            copied = (okCopy == true)
        end
        if copied then
            filesystem.remove(tmpPath)
            return true
        end

        if filesystem.exists(DB_PATH) then filesystem.remove(DB_PATH) end
        local renamed2 = filesystem.rename(tmpPath, DB_PATH)
        if renamed2 then return true end

        -- Оба способа не сработали — возвращаем прежнее содержимое, чтобы
        -- не потерять БД, и сообщаем об ошибке наверх.
        if original ~= nil then
            local dst = io.open(DB_PATH, "w")
            if dst then
                pcall(function() dst:write(original) end)
                dst:close()
            end
        end
        filesystem.remove(tmpPath)
        return false, "Ошибка сохранения БД"
    end
    return true
end

-- Получить данные игрока
function db.getPlayer(name)
    if data and data.players[name] then
        return data.players[name]
    end
    return nil
end

-- Зарегистрировать нового игрока
function db.registerPlayer(name)
    if data and not data.players[name] then
        data.players[name] = {
            role = "user",
            canWithdraw = true,
            canDeposit = true,
            canCraft = true,
            totalActions = 0,
            lastSeen = 0,
            banReason = "",
            banExpires = 0,
        }
        db.save()
        return true
    end
    return false
end

-- Проверить, является ли игрок админом (или выше)
function db.isAdmin(name)
    local level = db.getRoleLevel(name)
    return level >= db.ROLE_LEVELS["admin"]
end

-- Проверить, может ли игрок модерировать (банить юзеров)
function db.isModerator(name)
    local level = db.getRoleLevel(name)
    return level >= db.ROLE_LEVELS["moderator"]
end

-- ===== Персональные права =====
-- Флаги по умолчанию: включены (кроме забаненных)
local PERM_FIELDS = { "canWithdraw", "canDeposit", "canCraft" }
db.PERM_FIELDS = PERM_FIELDS

function db.getPermission(name, field)
    local p = db.getPlayer(name)
    if not p then return false end
    -- Забаненные и гости не могут совершать операции (гость — «только смотреть»)
    if p.role == "banned" or p.role == "guest" then return false end
    local v = p[field]
    if v == nil then return true end
    return v == true
end

function db.canWithdraw(name)
    if not db.getPermission(name, "canWithdraw") then return false end
    local cfg = db.getConfig()
    return cfg.allowUserWithdraw ~= false
end

function db.canDeposit(name)
    if not db.getPermission(name, "canDeposit") then return false end
    local cfg = db.getConfig()
    return cfg.allowUserDeposit ~= false
end

function db.canCraft(name)
    if not db.getPermission(name, "canCraft") then return false end
    local cfg = db.getConfig()
    return cfg.allowUserCraft ~= false
end

-- Переключить персональный флаг. Требует уровня администратора и
-- строгого превосходства над целью.
function db.setPermission(actorName, targetName, field, value)
    if not data or not data.players[targetName] then
        return false, "Игрок не найден"
    end

    local allowed = false
    for _, f in ipairs(PERM_FIELDS) do
        if f == field then allowed = true; break end
    end
    if not allowed then
        return false, "Неизвестное право: " .. tostring(field)
    end

    -- Админ может менять и свои флаги (например, отключить себе крафт)
    if actorName ~= targetName then
        local ok, err = db.hasPermission(actorName, targetName, "setPermission")
        if not ok then return false, err end
    else
        local actor = db.getPlayer(actorName)
        local level = actor and (db.ROLE_LEVELS[actor.role] or 0) or 0
        if level < db.ROLE_LEVELS["admin"] then
            return false, "Недостаточно прав для изменения прав"
        end
    end

    if value == nil then
        value = not (data.players[targetName][field] ~= false)
    end
    data.players[targetName][field] = (value == true)
    db.save()
    return true, data.players[targetName][field]
end

-- Установить роль игрока (с проверкой иерархии)
function db.setRole(actorName, targetName, newRole)
    if not data or not data.players[targetName] then
        return false, "Игрок не найден"
    end
    if db.ROLE_LEVELS[newRole] == nil then
        return false, "Неизвестная роль: " .. tostring(newRole)
    end

    -- Себе роль менять нельзя никому: иначе admin может выдать себе techadmin.
    if actorName == nil then
        return false, "Не указан игрок"
    end
    if actorName == targetName then
        return false, "Нельзя менять свою роль"
    end

    if targetName == "lixynhay" then
        return false, "Нельзя менять права Технического Администратора"
    end

    -- hasPermission: actor зарегистрирован, уровень >= admin, цель строго ниже.
    local ok, err = db.hasPermission(actorName, targetName, "setRole")
    if not ok then return false, err end

    -- Нельзя выдать роль не ниже своей (в том числе admin -> techadmin).
    local actorLevel = db.getRoleLevel(actorName)
    if (db.ROLE_LEVELS[newRole] or 0) >= actorLevel then
        return false, "Нельзя выдать роль не ниже своей"
    end

    data.players[targetName].role = newRole
    db.save()
    return true
end

-- Получить список всех игроков
function db.getAllPlayers()
    if data then
        return data.players
    end
    return {}
end

-- Получить глобальные настройки.
-- Всегда возвращает все три ключа allowUser*: отсутствующие/битые значения
-- заменяются дефолтами (true), даже если database.dat нет или он повреждён.
function db.getConfig()
    local cfg = defaultConfig()
    if data and type(data.config) == "table" then
        for key, value in pairs(data.config) do
            cfg[key] = value
        end
    end
    return cfg
end

-- Изменить глобальную настройку (публичный API для скриптов/medit, UI его
-- не вызывает). actor обязателен: прямые вызовы без прав запрещены.
function db.setConfig(actorName, key, value)
    if not actorName then return false, "forbidden" end
    local level = db.getRoleLevel(actorName)
    if level < (db.ROLE_LEVELS["admin"] or 4) then
        return false, "forbidden"
    end
    if not data then return false, "forbidden" end
    if type(key) ~= "string" or key == "" then
        return false, "Некорректный ключ"
    end
    if type(data.config) ~= "table" then data.config = defaultConfig() end
    data.config[key] = value
    db.save()
    return true
end

-- Получить лимиты предметов
function db.getThresholds()
    if not data then return {} end
    if not data.thresholds then data.thresholds = {} end
    return data.thresholds
end

-- Лимит конкретного предмета (или nil, если не настроен).
function db.getThreshold(itemName)
    if not data or not data.thresholds or not itemName then return nil end
    return data.thresholds[itemName]
end

-- Установить лимит предмета: itemName -> {label, min, autoCraft}; minAmount == 0 удаляет лимит.
-- actorName == nil — системный вызов (автокрафт), проверка прав пропускается.
-- autoCraft: nil — не менять текущее значение (совместимость со старыми вызовами).
function db.setThreshold(actorName, itemName, itemLabel, minAmount, autoCraft)
    if actorName ~= nil then
        local actor = db.getPlayer(actorName)
        local level = actor and (db.ROLE_LEVELS[actor.role] or 0) or 0
        if level < db.ROLE_LEVELS["admin"] then
            return false, "Недостаточно прав"
        end
    end
    if not data then return false end
    if not data.thresholds then data.thresholds = {} end
    if not itemName or itemName == "" then return false end
    if minAmount == 0 then
        data.thresholds[itemName] = nil
    else
        local prev = data.thresholds[itemName]
        local enabled
        if autoCraft == nil then
            -- Старые записи без флага ведут себя как «автокрафт включён».
            enabled = (prev == nil) or (prev.autoCraft ~= false)
        else
            enabled = (autoCraft == true)
        end
        data.thresholds[itemName] = {
            label = itemLabel or (prev and prev.label) or itemName,
            min = minAmount,
            autoCraft = enabled,
        }
    end
    db.save()
    return true
end

-- Добавить запись в лог операций (свежие сверху, максимум 200)
function db.addLog(player, action, item, amount)
    if not data then return end
    if not data.logs then data.logs = {} end
    
    local okT, t = pcall(os.time)
    local time = (okT and tonumber(t)) or 0
    local entry = {
        time = time,
        player = player or "Unknown",
        action = action, -- "take" (взял) или "put" (сдал)
        item = item or "Unknown",
        amount = math.floor(tonumber(amount) or 0)
    }
    
    table.insert(data.logs, 1, entry) -- свежие сверху
    if #data.logs > 200 then
        table.remove(data.logs)
    end

    -- Обновляем статистику профиля игрока
    if player and data.players and data.players[player] then
        local p = data.players[player]
        p.totalActions = (tonumber(p.totalActions) or 0) + 1
        p.lastSeen = time
    end

    db.save()
end

-- Последние N действий конкретного игрока (свежие первыми)
function db.getLogsForPlayer(name, limit)
    local out = {}
    if not name or not data or not data.logs then return out end
    limit = math.floor(tonumber(limit) or 5)
    if limit <= 0 then return out end

    for _, e in ipairs(data.logs) do
        if e and e.player == name then
            out[#out + 1] = e
            if #out >= limit then break end
        end
    end
    return out
end

-- Получить массив логов (свежие первыми).
-- Без аргументов — весь журнал. С playerName — только его записи (последние limit).
function db.getLogs(playerName, limit)
    if not data then return {} end
    if not data.logs then data.logs = {} end
    if playerName == nil then
        return data.logs
    end

    local out = {}
    local maxN = math.floor(tonumber(limit) or 10)
    if maxN <= 0 then return out end
    for _, e in ipairs(data.logs) do
        if e and e.player == playerName then
            out[#out + 1] = e
            if #out >= maxN then break end
        end
    end
    return out
end

-- Полностью очистить журнал операций.
-- actor обязателен: очистка доступна модератору и выше.
function db.clearLogs(actorName)
    if not actorName then return false, "forbidden" end
    local level = db.getRoleLevel(actorName)
    if level < (db.ROLE_LEVELS["moderator"] or 3) then
        return false, "forbidden"
    end
    if not data then return false, "Нет данных" end
    data.logs = {}
    db.save()
    return true
end

-- Забанить игрока. durationMinutes > 0 — временный бан, иначе навсегда
function db.banPlayer(actorName, targetName, reason, durationMinutes)
    if not data or not data.players[targetName] then return false, "Игрок не найден" end
    if targetName == "lixynhay" then
        return false, "Нельзя забанить Технического Администратора"
    end
    local ok, err = db.hasPermission(actorName, targetName, "ban")
    if not ok then return false, err end

    local okT, t = pcall(os.time)
    local now = (okT and tonumber(t)) or 0
    local expires = 0
    if durationMinutes and durationMinutes > 0 then
        expires = now + durationMinutes * 60
    end
    data.players[targetName].role = "banned"
    data.players[targetName].banReason = reason or ""
    data.players[targetName].banExpires = expires
    db.save()
    return true
end

-- Разбанить игрока. actorName == nil — системный вызов (например, авто-снятие бана).
function db.unbanPlayer(actorName, name)
    if not data or not data.players[name] then return false end
    if actorName ~= nil then
        local ok, err = db.hasPermission(actorName, name, "unban")
        if not ok then return false, err end
    end
    data.players[name].role = "user"
    data.players[name].banReason = ""
    data.players[name].banExpires = 0
    db.save()
    return true
end

-- Проверить бан: (true, {reason, expires}) если активен, иначе (false, nil).
-- Истёкший бан автоматически снимается.
function db.checkBan(name)
    if name == "lixynhay" then
        -- Иммунитет + самовосстановление роли (на случай старого/битого состояния БД)
        if data and data.players[name] and data.players[name].role ~= "techadmin" then
            data.players[name].role = "techadmin"
            data.players[name].banReason = ""
            data.players[name].banExpires = 0
            db.save()
        end
        return false, nil
    end
    if not data or not data.players[name] then return false, nil end
    local p = data.players[name]
    if p.role ~= "banned" then return false, nil end
    local okT, t = pcall(os.time)
    local now = (okT and tonumber(t)) or 0
    if p.banExpires and p.banExpires > 0 and now > 0 and now >= p.banExpires then
        p.role = "user"
        p.banReason = ""
        p.banExpires = 0
        db.save()
        return false, nil
    end
    return true, { reason = p.banReason or "", expires = p.banExpires or 0 }
end

return db
