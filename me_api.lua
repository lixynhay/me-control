local component = require("component")
local config = require("config")
local db = require("db")
local locale = require("locale")

local api = {}

-- Удаляет коды форматирования Minecraft (§a, §b, §k и т.д.) из строки
local function stripColor(text)
    if type(text) ~= "string" then return tostring(text) end
    -- Удаляем коды форматирования Minecraft (§a, §b, §k и т.д.)
    return text:gsub("§.", "")
end

-- Имя игрока, стоящего на PIM (для логов)
local function getPimPlayer()
    if not component.isAvailable("pim") then return "Unknown" end
    local ok, name = pcall(function() return component.pim.getInventoryName() end)
    if ok and name and name ~= "" then return name end
    return "Unknown"
end

-- Сколько предметов данного типа сейчас в МЭ (сначала по name, иначе по label)
local function getNetworkCount(itemName, itemLabel)
    local me = component.me_interface
    local ok, items = pcall(function() return me.getItemsInNetwork() end)
    if not ok or type(items) ~= "table" then return nil end
    local byName, anyName = 0, false
    local byLabel, anyLabel = 0, false
    for _, i in ipairs(items) do
        if itemName and i.name == itemName then
            byName = byName + (i.size or 0); anyName = true
        end
        if itemLabel and stripColor(i.label or "") == itemLabel then
            byLabel = byLabel + (i.size or 0); anyLabel = true
        end
    end
    if anyName then return byName end
    if anyLabel then return byLabel end
    return 0
end

-- Общее количество предметов в МЭ (для агрегированной проверки сдачи)
local function getTotalNetworkCount()
    local me = component.me_interface
    local ok, items = pcall(function() return me.getItemsInNetwork() end)
    if not ok or type(items) ~= "table" then return nil end
    local total = 0
    for _, i in ipairs(items) do total = total + (i.size or 0) end
    return total
end

-- Количество конкретного стека (name + damage) в МЭ
local function getNetworkCountByStack(itemName, itemDamage)
    if not itemName then return nil end
    local me = component.me_interface
    local ok, items = pcall(function() return me.getItemsInNetwork() end)
    if not ok or type(items) ~= "table" then return nil end
    local dmg = tonumber(itemDamage) or 0
    local total = 0
    for _, i in ipairs(items) do
        if i.name == itemName and (tonumber(i.damage) or 0) == dmg then
            total = total + (i.size or 0)
        end
    end
    return total
end

-- Получить предметы из МЭ
function api.getNetworkItems()
    local me = component.me_interface
    local ok, raw = pcall(function() return me.getItemsInNetwork() end)
    if not ok or type(raw) ~= "table" then return {} end
    local list = {}
    for _, i in pairs(raw) do 
        if i and (i.label or i.name) then 
            local lbl = i.label or i.name
            table.insert(list, {
                label = lbl, 
                display = locale.getName(i.name, i.damage, lbl),
                size = i.size, 
                name = i.name, 
                damage = i.damage,
                fingerprint = i.fingerprint -- Добавляем родной отпечаток МЭ
            }) 
        end 
    end
    table.sort(list, function(a, b) return (a.display or a.label) < (b.display or b.label) end)
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
                        display = locale.getName(itemName, itemDmg, itemLabel),
                        size = itemCount, 
                        name = itemName, 
                        damage = itemDmg,
                        fingerprint = stack.fingerprint
                    })
                end
            end
        end
    end
    
    table.sort(inv, function(a, b) return (a.display or a.label) < (b.display or b.label) end)
    return inv
end

-- Выдать игроку из МЭ (проверка успеха по фактическому уменьшению в сети)
function api.exportToPlayer(item, amount)
    local me = component.me_interface
    local realAmount = math.min(amount, item.size)
    if realAmount <= 0 then return false, "В МЭ нет предметов" end
    
    local itemDamage = item.damage or 0
    local countBefore = getNetworkCountByStack(item.name, itemDamage)
    
    local fp = item.fingerprint or {id = item.name, dmg = itemDamage}
    local ok, result = pcall(function()
        return me.exportItem(fp, config.side_export, realAmount, 0)
    end)
    if not ok then return false, "Ошибка API: " .. tostring(result) end
    
    -- Даём МЭ обновить данные и считаем фактическую выдачу
    os.sleep(0.2)
    local countAfter = getNetworkCountByStack(item.name, itemDamage)
    
    local actuallyExported = 0
    if countBefore ~= nil and countAfter ~= nil then
        actuallyExported = countBefore - countAfter
    end
    if actuallyExported < 0 then actuallyExported = 0 end
    
    if actuallyExported > 0 then
        db.addLog(getPimPlayer(), "take", item.display or item.label, actuallyExported)
        return true, "Выдано: " .. actuallyExported .. " шт."
    end
    return false, "МЭ отказала в выдаче (0 шт.)"
end

-- Забрать у игрока в МЭ через pim.pushItem + проверка на выпадение в мир
function api.pushFromPlayer(item, amount)
    local pim = component.pim
    local me = component.me_interface
    local itemLabel, itemName
    if type(item) == "table" then
        itemLabel = item.label or item.name
        itemName = item.name or item.label
    else
        itemLabel = item
        itemName = item
    end

    local moved = 0
    local okSize, size = pcall(function() return pim.getInventorySize() end)
    if not okSize or not size then return false, "PIM недоступен" end
    size = math.floor(tonumber(size) or 0)
    if size == 0 then return false, "Инвентарь пуст" end

    -- Запоминаем количество в МЭ до выталкивания
    local countBefore = getNetworkCount(itemName, itemLabel)

    for slot = 1, size do
        local sOk, stack = pcall(function() return pim.getStackInSlot(slot) end)
        if sOk and stack then
            -- Поддержка форматов OpenPeripheral (display_name / qty) и OC (label / size)
            local stackLabel = stripColor(stack.display_name or stack.label or stack.name)
            local stackCount = stack.qty or stack.size or 0
            if stackLabel == itemLabel and stackCount > 0 then
                local want = math.min(amount - moved, stackCount)
                if want > 0 then
                    local pOk, pushed = pcall(function() return pim.pushItem(config.side_push, slot, want) end)
                    if pOk and tonumber(pushed) then moved = moved + tonumber(pushed) end
                    if moved >= amount then break end
                end
            end
        end
    end

    if moved == 0 then
        return false, "Предмет не найден или МЭ не приняла его"
    end

    -- Даём МЭ время обработать и сверяем количество
    os.sleep(0.5)
    local countAfter = getNetworkCount(itemName, itemLabel)
    if countBefore ~= nil and countAfter ~= nil then
        local accepted = countAfter - countBefore
        if accepted < 0 then accepted = 0 end
        local lost = moved - accepted
        if lost > 0 then
            -- Опционально: вернуть предмет обратно в PIM, если есть fingerprint
            local fp = (type(item) == "table") and item.fingerprint or nil
            if fp then
                local eOk, exported = pcall(function() return me.exportItem(fp, config.side_export, lost, 0) end)
                if eOk and tonumber(exported) and tonumber(exported) > 0 then
                    return false, "Предмет возвращен в инвентарь (МЭ не приняла его)"
                end
            end
            return false, "ВНИМАНИЕ: Предмет не попал в МЭ-сеть! Он остался в ME Interface. Заберите его оттуда вручную."
        end
    end

    db.addLog(getPimPlayer(), "put", (type(item) == "table" and item.display) or itemLabel, moved)
    if moved >= amount then
        return true, "Сдано: " .. moved .. " шт."
    end
    return false, "МЭ приняла только " .. moved .. " из " .. amount .. " шт. Остальное осталось в инвентаре"
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

-- Суммирует показатели одной ячейки/диска в накопитель acc.
-- Поля могут называться по-разному в зависимости от версии OC/AE, поэтому
-- принимаем несколько вариантов имён. Возвращает true, если данные найдены.
local function addStorageEntry(acc, cell)
    if type(cell) ~= "table" then return false end

    -- Вложенные ячейки (например, диск с массивом cells/storage)
    local nested = cell.cells or cell.storage
    if type(nested) == "table" then
        local any = false
        for _, c in pairs(nested) do
            if addStorageEntry(acc, c) then any = true end
        end
        if any then return true end
    end

    local totalBytes = tonumber(cell.totalBytes or cell.totalbytes or cell.bytesTotal or cell.total)
    local usedBytes  = tonumber(cell.usedBytes  or cell.usedbytes  or cell.bytesUsed)
    local totalTypes = tonumber(cell.totalTypes or cell.totaltypes or cell.typesTotal)
    local usedTypes  = tonumber(cell.usedTypes  or cell.usedtypes  or cell.typesUsed)

    if not totalBytes and not usedBytes and not totalTypes and not usedTypes then
        return false
    end

    acc.totalBytes = acc.totalBytes + (totalBytes or 0)
    acc.usedBytes  = acc.usedBytes  + (usedBytes  or 0)
    acc.totalTypes = acc.totalTypes + (totalTypes or 0)
    acc.usedTypes  = acc.usedTypes  + (usedTypes  or 0)
    return true
end

-- Информация о хранилище МЭ (ячейки/диски): объём и количество типов.
-- В части версий OC у me_interface есть getCells()/getDrives(); если их нет,
-- оцениваем занятое по списку предметов сети (формула AE2: 8 предметов = 1 байт,
-- каждый тип = 8 байт). Точный общий объём без getCells() недоступен.
function api.getStorageInfo()
    local okMe, me = pcall(function() return component.me_interface end)
    if not okMe or not me then return nil end

    local acc = { totalBytes = 0, usedBytes = 0, totalTypes = 0, usedTypes = 0 }
    local found = false

    -- 1) Список ячеек сети (OC с интеграцией AE2, где метод реализован)
    local okCellsFn, cellsFn = pcall(function() return me.getCells end)
    if okCellsFn and type(cellsFn) == "function" then
        local ok, cells = pcall(function() return me.getCells() end)
        if ok and type(cells) == "table" then
            for _, cell in pairs(cells) do
                if addStorageEntry(acc, cell) then found = true end
            end
        end
    end

    -- 2) Альтернатива: список дисков
    local okDrivesFn, drivesFn = pcall(function() return me.getDrives end)
    if not found and okDrivesFn and type(drivesFn) == "function" then
        local ok, drives = pcall(function() return me.getDrives() end)
        if ok and type(drives) == "table" then
            for _, drive in pairs(drives) do
                if addStorageEntry(acc, drive) then found = true end
            end
        end
    end

    if found and (acc.totalBytes > 0 or acc.totalTypes > 0) then
        return acc
    end

    -- 3) Резерв: метода нет (например, OC 1.7.10). Считаем занятое по предметам.
    local items = api.getNetworkItems()
    if type(items) ~= "table" or #items == 0 then return nil end

    local totalItems = 0
    for _, it in ipairs(items) do
        totalItems = totalItems + (tonumber(it.size) or 0)
    end
    if totalItems <= 0 then return nil end

    local usedTypes = #items
    return {
        totalBytes = nil,
        usedBytes = math.ceil(totalItems / 8) + usedTypes * 8,
        totalTypes = nil,
        usedTypes = usedTypes,
        estimated = true,
    }
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

-- Сдать весь инвентарь игрока в МЭ через pim.pushItem
function api.depositAll()
    local pim = component.pim
    local moved = 0
    local okSize, size = pcall(function() return pim.getInventorySize() end)
    if not okSize or not size then return 0, "PIM недоступен" end
    size = math.floor(tonumber(size) or 0)
    if size == 0 then return 0, "Инвентарь пуст" end
    
    local totalBefore = getTotalNetworkCount()
    local deposited = {} -- label -> count
    
    for slot = 1, size do
        local sOk, stack = pcall(function() return pim.getStackInSlot(slot) end)
        if sOk and stack then
            -- Поддержка форматов OpenPeripheral (qty) и OC (size)
            local stackCount = stack.qty or stack.size or 0
            if stackCount > 0 then
                local pOk, pushed = pcall(function() return pim.pushItem(config.side_push, slot, stackCount) end)
                if pOk and tonumber(pushed) and tonumber(pushed) > 0 then
                    local n = tonumber(pushed)
                    moved = moved + n
                    local rawLbl = stripColor(stack.display_name or stack.label or stack.name or "Неизвестный предмет")
                    local lbl = locale.getName(stack.id or stack.name, tonumber(stack.damage) or tonumber(stack.dmg) or 0, rawLbl)
                    deposited[lbl] = (deposited[lbl] or 0) + n
                end
            end
        end
    end
    if moved == 0 then
        return 0, "Нечего сдавать"
    end
    
    -- Логируем массовую сдачу по каждому предмету
    local player = getPimPlayer()
    for lbl, n in pairs(deposited) do
        db.addLog(player, "put", lbl, n)
    end
    
    -- Проверка: всё ли реально попало в МЭ
    os.sleep(0.5)
    local totalAfter = getTotalNetworkCount()
    if totalBefore ~= nil and totalAfter ~= nil and (totalAfter - totalBefore) < moved then
        return moved, "ВНИМАНИЕ: Некоторые предметы не попали в сеть! Заберите их из ME Interface вручную."
    end
    return moved, "Сдано всё: " .. moved .. " шт."
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