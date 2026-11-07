local component = require("component")
local config = require("config")
local db = require("db")

local api = {}

-- Удаляет коды форматирования Minecraft (§a, §b, §k и т.д.) из строки
local function stripColor(text)
    if type(text) ~= "string" then return tostring(text) end
    -- Удаляем коды форматирования Minecraft (§a, §b, §k и т.д.)
    return text:gsub("§.", "")
end

-- Получить предметы из МЭ
function api.getNetworkItems()
    local me = component.me_interface
    local ok, raw = pcall(function() return me.getItemsInNetwork() end)
    if not ok or type(raw) ~= "table" then return {} end
    local list = {}
    for _, i in pairs(raw) do 
        if i and i.label then 
            table.insert(list, {
                label = i.label, 
                size = i.size, 
                name = i.name, 
                damage = i.damage,
                fingerprint = i.fingerprint -- Добавляем родной отпечаток МЭ
            }) 
        end 
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

-- Получить инвентарь игрока (с поддержкой формата OpenPeripheral Addon)
function api.getPlayerInventory()
    local inv = {}
    if not api.isPlayerPresent() then return inv end
    
    local pim = component.pim
    local okSize, size = pcall(function() return pim.getInventorySize() end)
    if not okSize or not size then return inv end
    size = math.floor(tonumber(size) or 0)
    if size == 0 then return inv end

    for slot = 1, size do
        local sOk, stack = pcall(function() return pim.getStackInSlot(slot) end)
        if sOk and stack then
            -- Поддержка форматов OpenPeripheral (display_name / qty) и OC (label / size)
            local itemLabel = stripColor(stack.display_name or stack.label or stack.name or "Неизвестный предмет")
            local itemCount = math.floor(tonumber(stack.qty) or tonumber(stack.size) or 0)
            local itemName  = stack.id or stack.name or itemLabel
            local itemDmg   = math.floor(tonumber(stack.damage) or tonumber(stack.dmg) or 0)
            
            if itemCount > 0 then
                local found = false
                for _, item in ipairs(inv) do
                    if item.label == itemLabel and item.damage == itemDmg then
                        item.size = item.size + itemCount
                        found = true
                        break
                    end
                end
                if not found then
                    table.insert(inv, {
                        label = itemLabel, 
                        size = itemCount, 
                        name = itemName, 
                        damage = itemDmg
                    })
                end
            end
        end
    end
    
    table.sort(inv, function(a, b) return a.label < b.label end)
    return inv
end

-- Выдать игроку из МЭ
function api.exportToPlayer(item, amount)
    local me = component.me_interface
    local realAmount = math.min(amount, item.size)
    if realAmount <= 0 then return false, "В МЭ нет предметов" end
    
    local fp = item.fingerprint or {id = item.name, dmg = item.damage or 0}
    local ok, result = pcall(function()
        return me.exportItem(fp, config.side_export, realAmount, 0)
    end)
    if not ok then return false, "Ошибка API: " .. tostring(result) end
    local exported = tonumber(result) or 0
    if exported > 0 then return true, "Выдано: " .. exported .. " шт."
    else return false, "МЭ отказала в выдаче (0 шт.)" end
end

-- Забрать у игрока в МЭ (через me.importItem, чтобы предметы не выбрасывались в мир)
function api.pushFromPlayer(itemLabel, amount)
    local pim = component.pim
    local me = component.me_interface
    local moved = 0
    local okSize, size = pcall(function() return pim.getInventorySize() end)
    if not okSize or not size then return false, "PIM недоступен" end
    size = math.floor(tonumber(size) or 0)
    if size == 0 then return false, "Инвентарь пуст" end
    
    for slot = 1, size do
        local sOk, stack = pcall(function() return pim.getStackInSlot(slot) end)
        if sOk and stack then
            -- Поддержка форматов OpenPeripheral (display_name / qty) и OC (label / size)
            local stackLabel = stripColor(stack.display_name or stack.label or stack.name)
            local stackCount = stack.qty or stack.size or 0
            if stackLabel == itemLabel and stackCount > 0 then
                local want = math.min(amount - moved, stackCount)
                if want > 0 then
                    local iOk, imported = pcall(function() return me.importItem(config.side_import, slot, want) end)
                    if iOk and tonumber(imported) then
                        moved = moved + tonumber(imported)
                    end
                    if moved >= amount then break end
                end
            end
        end
    end
    
    if moved >= amount then
        return true, "Сдано: " .. moved .. " шт."
    elseif moved > 0 then
        return false, "МЭ приняла только " .. moved .. " из " .. amount .. " шт. Остальное осталось в инвентаре"
    else
        return false, "МЭ отказалась принимать " .. itemLabel .. ". Предмет остался в инвентаре"
    end
end

-- Проверка наличия игрока
function api.isPlayerPresent()
    local pim = component.pim
    local ok, name = pcall(function() return pim.getInventoryName() end)
    if not ok then return false end
    return name ~= nil and name ~= ""
end

-- Проверки прав
function api.canWithdraw(playerName)
    if not playerName then return false end
    local player = db.getPlayer(playerName)
    if not player or player.role == "banned" then return false end
    return db.getConfig().allowUserWithdraw ~= false
end

function api.canDeposit(playerName)
    if not playerName then return false end
    local player = db.getPlayer(playerName)
    if not player or player.role == "banned" then return false end
    return db.getConfig().allowUserDeposit ~= false
end

-- Получить информацию о МЭ-сети (для вкладки «Статистика»)
function api.getNetworkInfo()
    local me = component.me_interface
    local info = { totalItems = 0, totalTypes = 0, energyStored = nil, energyMax = nil, cpus = nil }
    
    -- Считаем предметы
    local okItems, items = pcall(function() return me.getItemsInNetwork() end)
    if okItems and type(items) == "table" then
        info.totalTypes = #items
        for _, item in ipairs(items) do
            info.totalItems = info.totalItems + (item.size or 0)
        end
    end
    
    -- Пробуем получить энергию через me_controller
    if component.isAvailable("me_controller") then
        local ctrl = component.me_controller
        local okE, eStored = pcall(function() return ctrl.getEnergyStored() end)
        if okE then info.energyStored = eStored end
        local okM, eMax = pcall(function() return ctrl.getMaxEnergyStored() end)
        if okM then info.energyMax = eMax end
    end
    
    -- Пробуем получить список сопроцессоров (если метод есть)
    if me and me.getCpus then
        local ok, cpus = pcall(function() return me.getCpus() end)
        if ok and cpus then
            info.cpus = #cpus
        end
    end
    
    return info
end

-- Статус по лимитам: массив {label, current, min, isOk}, отсортирован по имени
function api.getThresholdStatus()
    local list = {}
    local thresholds = db.getThresholds()
    local me = component.me_interface
    
    -- Карта текущих количеств по имени предмета
    local currentMap = {}
    local okItems, items = pcall(function() return me.getItemsInNetwork() end)
    if okItems and type(items) == "table" then
        for _, item in ipairs(items) do
            if item and item.name then
                currentMap[item.name] = (currentMap[item.name] or 0) + (item.size or 0)
            end
        end
    end
    
    for name, th in pairs(thresholds) do
        local current = currentMap[name] or 0
        table.insert(list, {
            label = th.label or name,
            current = current,
            min = th.min,
            isOk = current >= th.min
        })
    end
    
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

-- Сдать весь инвентарь игрока в МЭ (через me.importItem)
function api.depositAll()
    local pim = component.pim
    local me = component.me_interface
    local moved = 0
    local okSize, size = pcall(function() return pim.getInventorySize() end)
    if not okSize or not size then return 0, "PIM недоступен" end
    size = math.floor(tonumber(size) or 0)
    if size == 0 then return 0, "Инвентарь пуст" end
    
    for slot = 1, size do
        local sOk, stack = pcall(function() return pim.getStackInSlot(slot) end)
        if sOk and stack then
            -- Поддержка форматов OpenPeripheral (qty) и OC (size)
            local stackCount = stack.qty or stack.size or 0
            if stackCount > 0 then
                local iOk, imported = pcall(function() return me.importItem(config.side_import, slot, stackCount) end)
                if iOk and tonumber(imported) then
                    moved = moved + tonumber(imported)
                end
            end
        end
    end
    if moved > 0 then
        return moved, "Сдано всё: " .. moved .. " шт."
    end
    return 0, "МЭ отказалась принимать предметы. Инвентарь не изменён"
end

-- Проверка: есть ли хотя бы один предмет со статусом «МАЛО»
function api.hasAlert()
    local status = api.getThresholdStatus()
    for _, item in ipairs(status) do
        if not item.isOk then return true end
    end
    return false
end

return api