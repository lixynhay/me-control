local serialization = require("serialization")
local filesystem = require("filesystem")

local db = {}
local DB_PATH = "/home/database.dat"
local data = nil

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

function db.getRoleName(name)
    local p = db.getPlayer(name)
    return p and p.role or nil
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
    if action == "ban" and actorLevel < 3 then
        return false, "Банить могут модераторы и выше"
    end
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
    if filesystem.exists(DB_PATH) then
        local file = io.open(DB_PATH, "r")
        if file then
            local content = file:read("*a")
            file:close()
            local ok, loaded = pcall(serialization.unserialize, content)
            if ok and type(loaded) == "table" then
                data = loaded
                data.players = data.players or {}
                data.config = data.config or { allowUserWithdraw = true, allowUserDeposit = true }
                data.thresholds = data.thresholds or {}
                data.logs = data.logs or {}
                for _, p in pairs(data.players) do
                    if p.banReason == nil then p.banReason = "" end
                    if p.banExpires == nil then p.banExpires = 0 end
                    -- Миграция: персональные права (появились в v1.7.0)
                    if p.canWithdraw == nil then p.canWithdraw = true end
                    if p.canDeposit == nil then p.canDeposit = true end
                    if p.canCraft == nil then p.canCraft = true end
                    -- Миграция: статистика профиля (v1.7.1)
                    if p.totalActions == nil then p.totalActions = 0 end
                    if p.lastSeen == nil then p.lastSeen = 0 end
                end
            end
        end
    end
    
    -- Если файла нет или он поврежден, создаем структуру по умолчанию
    if not data then
        data = {
            players = {
                ["lixynhay"] = { role = "admin" }
            },
            config = {
                allowUserWithdraw = true,
                allowUserDeposit = true
            },
            thresholds = {},
            logs = {}
        }
        db.save() -- Сразу сохраняем стандартные настройки
    end
    
    -- Технический администратор: роль всегда techadmin, аккаунт создаётся при необходимости
    if data.players["lixynhay"] then
        local p = data.players["lixynhay"]
        p.role = "techadmin"
        if p.canWithdraw == nil then p.canWithdraw = true end
        if p.canDeposit == nil then p.canDeposit = true end
        if p.canCraft == nil then p.canCraft = true end
        if p.totalActions == nil then p.totalActions = 0 end
        if p.lastSeen == nil then p.lastSeen = 0 end
    else
        data.players["lixynhay"] = {
            role = "techadmin",
            canWithdraw = true, canDeposit = true, canCraft = true,
            totalActions = 0, lastSeen = 0,
            banReason = "", banExpires = 0,
        }
    end
    db.save()
end

-- Сохранение базы данных в файл
function db.save()
    if data then
        local content = serialization.serialize(data)
        local file = io.open(DB_PATH, "w")
        if file then
            file:write(content)
            file:close()
        end
    end
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
    if targetName == "lixynhay" then
        if actorName ~= "lixynhay" then
            return false, "Нельзя менять права Технического Администратора"
        end
        if newRole ~= "techadmin" then
            return false, "Роль techadmin нельзя снять"
        end
    end

    -- Себе роль менять нельзя; над другими — только если ты строго выше
    if actorName ~= targetName then
        local ok, err = db.hasPermission(actorName, targetName, "setRole")
        if not ok then return false, err end

        -- Нельзя выдать роль не ниже своей
        local actorLevel = db.getRoleLevel(actorName)
        if (db.ROLE_LEVELS[newRole] or 0) >= actorLevel then
            return false, "Нельзя выдать роль не ниже своей"
        end
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

-- Получить глобальные настройки
function db.getConfig()
    return data and data.config or {}
end

-- Изменить глобальную настройку
function db.setConfig(key, value)
    if data and data.config then
        data.config[key] = value
        db.save()
    end
end

-- Получить лимиты предметов
function db.getThresholds()
    if not data then return {} end
    if not data.thresholds then data.thresholds = {} end
    return data.thresholds
end

-- Установить лимит предмета: itemName -> {label, min}; minAmount == 0 удаляет лимит
function db.setThreshold(itemName, itemLabel, minAmount)
    if not data then return false end
    if not data.thresholds then data.thresholds = {} end
    if not itemName or itemName == "" then return false end
    if minAmount == 0 then
        data.thresholds[itemName] = nil
    else
        data.thresholds[itemName] = { label = itemLabel or itemName, min = minAmount }
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

-- Получить массив логов (свежие первыми)
function db.getLogs()
    if not data then return {} end
    if not data.logs then data.logs = {} end
    return data.logs
end

-- Полностью очистить журнал операций
function db.clearLogs()
    if not data then return false end
    data.logs = {}
    db.save()
    return true
end

-- Сколько записей в журнале
function db.getLogsCount()
    if not data or not data.logs then return 0 end
    return #data.logs
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

-- Разбанить игрока
function db.unbanPlayer(name)
    if not data or not data.players[name] then return false end
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
