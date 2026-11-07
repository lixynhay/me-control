local serialization = require("serialization")
local filesystem = require("filesystem")

local db = {}
local DB_PATH = "/home/database.dat"
local data = nil

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
        data.players["lixynhay"].role = "techadmin"
    else
        data.players["lixynhay"] = { role = "techadmin", banReason = "", banExpires = 0 }
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
        data.players[name] = { role = "user", banReason = "", banExpires = 0 }
        db.save()
        return true
    end
    return false
end

-- Проверить, является ли игрок админом
function db.isAdmin(name)
    local player = db.getPlayer(name)
    return player ~= nil and (player.role == "admin" or player.role == "techadmin")
end

-- Установить роль игрока
function db.setRole(actorName, targetName, newRole)
    if not db.isAdmin(actorName) then
        return false, "Недостаточно прав для выполнения операции"
    end
    if not data or not data.players[targetName] then
        return false, "Игрок не найден"
    end
    if targetName == "lixynhay" then
        if actorName ~= "lixynhay" then
            return false, "Нельзя менять права Технического Администратора"
        end
        if newRole ~= "techadmin" then
            return false, "Роль techadmin нельзя снять"
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
        amount = amount or 0
    }
    
    table.insert(data.logs, 1, entry) -- свежие сверху
    if #data.logs > 200 then
        table.remove(data.logs)
    end
    db.save()
end

-- Получить массив логов (свежие первыми)
function db.getLogs()
    if not data then return {} end
    if not data.logs then data.logs = {} end
    return data.logs
end

-- Забанить игрока. durationMinutes > 0 — временный бан, иначе навсегда
function db.banPlayer(actorName, targetName, reason, durationMinutes)
    if not db.isAdmin(actorName) then
        return false, "Недостаточно прав для выполнения операции"
    end
    if not data or not data.players[targetName] then return false, "Игрок не найден" end
    if targetName == "lixynhay" and actorName ~= "lixynhay" then
        return false, "Нельзя забанить Технического Администратора"
    end
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
    if name == "lixynhay" then return false, nil end
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
