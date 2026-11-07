local component = require("component")
local config = require("config")
local db = require("db")
local locale = require("locale")
local unicode = require("unicode")

local api = {}

-- Удаляет коды форматирования Minecraft (§a, §b, §k и т.д.) из строки
local function stripColor(text)
    if type(text) ~= "string" then return tostring(text) end
    -- Удаляем коды форматирования Minecraft (§a, §b, §k и т.д.)
    return text:gsub("§.", "")
end

-- Человекочитаемая причина отказа в персональном праве
local function denyReason(playerName, field, label)
    local p = db.getPlayer(playerName)
    if not p then
        return "Нет активного пользователя (встаньте на PIM)"
    end
    if p.role == "banned" then
        return "Доступ запрещён: вы забанены"
    end
    if p[field] == false then
        return "Вам запрещено: " .. label
    end
    local cfg = db.getConfig()
    if field == "canWithdraw" and cfg.allowUserWithdraw == false then
        return "Вам запрещено: " .. label
    end
    if field == "canDeposit" and cfg.allowUserDeposit == false then
        return "Вам запрещено: " .. label
    end
    if field == "canCraft" and cfg.allowUserCraft == false then
        return "Вам запрещено: " .. label
    end
    return "Вам запрещено: " .. label
end

-- Проверка права с возвратом причины отказа (nil, если можно)
local function checkPermission(playerName, field, label)
    local allowed
    if field == "canWithdraw" then allowed = db.canWithdraw(playerName)
    elseif field == "canDeposit" then allowed = db.canDeposit(playerName)
    else allowed = db.canCraft(playerName) end

    if allowed then return nil end
    return denyReason(playerName, field, label)
end

-- Убирает «сырую» обёртку ключа локализации из названия предмета:
--   item.appliedenergistics2.ItemMaterial.CardAdvSpeed.name -> CardAdvSpeed
--   tile.foo.bar.name                                       -> bar
-- Также снимает префикс пространства имён (mod:item_name -> item_name),
-- если человекочитаемого имени так и не нашлось.
local function cleanLabel(text)
    if type(text) ~= "string" then return text end
    local s = text

    -- item.<...>.name / tile.<...>.name
    s = s:gsub("^item%.", ""):gsub("^tile%.", "")
    s = s:gsub("%.name$", "")

    -- Если остался «путь» из сегментов — берём последний осмысленный сегмент
    if s:find("%.") and not s:find("%s") then
        local last = s:match("([^%.]+)$")
        if last and last ~= "" then s = last end
    end

    -- registry-имя вида mod:item_name -> item_name
    s = s:gsub("^[%w_%-]+:", "")

    -- Подчёркивания -> пробелы, каждое слово с заглавной
    if s:find("_") and not s:find("%s") then
        s = s:gsub("_", " ")
        s = s:gsub("(%a)([%w']*)", function(first, rest)
            return first:upper() .. rest
        end)
    end

    return s
end

api.cleanLabel = cleanLabel

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

-- Сортировка списка предметов.
--   mode = "alpha" — по названию (А-Я), "desc" — по количеству убыв., "asc" — возр.
-- Сортирует переданный список на месте и возвращает его же.
local function itemName(entry)
    if type(entry) ~= "table" then return "" end
    local n = entry.display or entry.label or entry.name or ""
    return unicode.lower(tostring(n))
end

local function itemSize(entry)
    if type(entry) ~= "table" then return 0 end
    return tonumber(entry.size) or 0
end

function api.sortItems(items, mode)
    if type(items) ~= "table" then return items end
    if mode == "desc" then
        table.sort(items, function(a, b)
            local sa, sb = itemSize(a), itemSize(b)
            if sa ~= sb then return sa > sb end
            return itemName(a) < itemName(b)
        end)
    elseif mode == "asc" then
        table.sort(items, function(a, b)
            local sa, sb = itemSize(a), itemSize(b)
            if sa ~= sb then return sa < sb end
            return itemName(a) < itemName(b)
        end)
    else
        -- alpha (по умолчанию): по отображаемому имени, при равенстве — по количеству
        table.sort(items, function(a, b)
            local na, nb = itemName(a), itemName(b)
            if na ~= nb then return na < nb end
            return itemSize(a) > itemSize(b)
        end)
    end
    return items
end

-- Чистит текст ошибки Lua: убирает путь к файлу и номер строки.
local function cleanError(err)
    local msg = tostring(err or "неизвестная ошибка")
    -- "C:\path\file.lua:27: text"  или  "file.lua:12: text"
    local short = msg:match("^.-[\\/][^\\/]-:%d+:%s*(.+)$")
    if not short then short = msg:match("^.-:%d+:%s*(.+)$") end
    return short or msg
end

-- Вызывает метод компонента и нормализует результат.
--
-- В OpenComputers метод может быть не только функцией: прокси-объект бывает
-- таблицей с метаметодом __call. Поэтому тип НЕ проверяем, а просто пробуем
-- вызвать: obj[name]() — для таблицы с __call это тоже валидный вызов.
-- Если прямой вызов упал, дополнительно дёргаем __call из метатаблицы.
--
-- Возвращает: true, результат | false, текст ошибки
local function callComponentMethod(obj, name)
    if obj == nil then
        return false, "компонент недоступен"
    end

    local okValue, value = pcall(function() return obj[name] end)
    if not okValue then
        return false, cleanError(value)
    end
    if value == nil then
        return false, "метод отсутствует (nil)"
    end
    -- 1) Прямой вызов с круглыми скобками
    local ok, result = pcall(function() return obj[name]() end)
    if ok then
        return true, result
    end
    local firstErr = cleanError(result)

    -- 2) Если вызвать напрямую не получилось — проверяем __call в метатаблице
    local okMt, mt = pcall(getmetatable, value)
    if okMt and type(mt) == "table" and mt.__call ~= nil then
        local ok2, result2 = pcall(function() return mt.__call(value) end)
        if ok2 then
            return true, result2
        end
        return false, cleanError(result2)
    end

    -- 3) Понятное сообщение, если объект в принципе не вызываемый
    local vtype = type(value)
    if vtype ~= "function" then
        return false, vtype .. " без __call"
    end

    return false, firstErr
end

-- Список доступных крафтов (рецептов) в МЭ-сети.
-- Каждый элемент: { label, display, name, damage, size, craftable }
-- где craftable — исходный объект-рецепт (нужен для request()).
--
-- Диагностика: причина неудачи (если список пуст) пишется в _G.last_craft_error.
-- Это удобно показывать в статус-баре и в test_craft.lua.
function api.getCraftables()
    _G.last_craft_error = nil

    local okMe, me = pcall(function() return component.me_interface end)
    if not okMe then
        _G.last_craft_error = "me_interface: " .. cleanError(me)
        return {}
    end
    if not me then
        _G.last_craft_error = "me_interface недоступен"
        return {}
    end

    -- Просто пробуем вызвать — без проверки type(...) == "function"
    local okRaw, raw = callComponentMethod(me, "getCraftables")
    if not okRaw then
        _G.last_craft_error = "getCraftables: " .. tostring(raw)
        return {}
    end
    if type(raw) ~= "table" then
        _G.last_craft_error = "getCraftables вернул " .. type(raw) .. " вместо table"
        return {}
    end

    -- Текущие количества в сети (одним запросом, чтобы показать «В сети:»)
    local counts = {}
    local okItems, items = pcall(function() return me.getItemsInNetwork() end)
    if okItems and type(items) == "table" then
        for _, i in ipairs(items) do
            if i and i.name then
                local key = tostring(i.name) .. "@" .. tostring(tonumber(i.damage) or 0)
                counts[key] = (counts[key] or 0) + (tonumber(i.size) or 0)
            end
        end
    end

    local list = {}
    local stackErrors = 0
    for _, c in pairs(raw) do
        if c then
            local okStack, stack = pcall(function() return c.getItemStack() end)
            if okStack and type(stack) == "table" then
                local label = stripColor(stack.label or stack.display_name or stack.name or "?")
                local itemName = stack.name
                local dmg = tonumber(stack.damage) or 0
                local key = tostring(itemName) .. "@" .. tostring(dmg)
                table.insert(list, {
                    label = label,
                    display = cleanLabel(locale.getName(itemName, dmg, label)),
                    name = itemName,
                    damage = dmg,
                    size = counts[key] or 0,
                    craftable = c,
                })
            else
                stackErrors = stackErrors + 1
            end
        end
    end

    -- Рецепты есть, но ни у одного не удалось прочитать getItemStack()
    if #list == 0 and stackErrors > 0 then
        _G.last_craft_error = "getItemStack() не сработал у всех " .. tostring(stackErrors) .. " рецептов"
    end

    table.sort(list, function(a, b)
        local na = unicode.lower(tostring(a.display or a.label or ""))
        local nb = unicode.lower(tostring(b.display or b.label or ""))
        if na ~= nb then return na < nb end
        return tostring(a.label or "") < tostring(b.label or "")
    end)
    return list
end

-- Безопасно вызывает метод у объекта статуса (userdata/table).
-- Возвращает true/false, либо nil если метода нет или вызов упал.
local function tryStatusCall(obj, method)
    if obj == nil then return nil end
    local okRef, fn = pcall(function() return obj[method] end)
    if not okRef or fn == nil then return nil end
    local okCall, res = pcall(function() return obj[method]() end)
    if not okCall then return nil end
    if type(res) == "boolean" then return res end
    if type(res) == "number" then return res ~= 0 end
    return nil
end

-- Разбор объекта статуса крафта (то, что вернул craftable.request()).
-- Класс CraftingStatus в OC/AE2 отдаёт isDone() и isCanceled(); hasFailed()
-- есть не во всех сборках, поэтому проверяем его наличие необязательно.
-- Возвращает таблицу { done, canceled, failed, computing } (nil = метод недоступен).
function api.getCraftStatus(status)
    if status == nil then return nil end
    return {
        done      = tryStatusCall(status, "isDone"),
        canceled  = tryStatusCall(status, "isCanceled"),
        failed    = tryStatusCall(status, "hasFailed"),
        computing = tryStatusCall(status, "isComputing"),
    }
end

-- Отправить запрос на крафт. Принимает либо объект-рецепт, либо элемент списка.
-- Возвращает: true, "Запрос отправлен", статус (для отслеживания прогресса)
--          или false, "текст причины"
function api.requestCraft(craftableObject, amount)
    -- Персональное право: крафт
    local playerName = getPimPlayer()
    local denied = checkPermission(playerName, "canCraft", "заказывать крафт")
    if denied then return false, denied end

    local target = craftableObject
    if type(target) == "table" and target.craftable ~= nil then
        target = target.craftable
    end
    if target == nil then
        return false, "Рецепт недоступен"
    end

    amount = math.floor(tonumber(amount) or 1)
    if amount < 1 then amount = 1 end

    local ok, result = pcall(function() return target.request(amount) end)
    if not ok then
        return false, cleanError(result)
    end
    if result == nil then
        return false, "МЭ-сеть не вернула статус крафта"
    end
    if result == false then
        return false, "МЭ-сеть отклонила запрос на крафт"
    end

    -- Пробуем сразу понять состояние: если запрос успел провалиться — сообщаем
    local st = api.getCraftStatus(result)
    if st and st.failed == true then
        return false, "Крафт сразу провален: нет ресурсов или занят CPU"
    end

    return true, "Запрос отправлен", result
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
                display = cleanLabel(locale.getName(i.name, i.damage, lbl)),
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
                        display = cleanLabel(locale.getName(itemName, itemDmg, itemLabel)),
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
    -- Персональное право: забор из МЭ
    local playerName = getPimPlayer()
    local denied = checkPermission(playerName, "canWithdraw", "забирать предметы")
    if denied then return false, denied end

    local me = component.me_interface
    local realAmount = math.min(amount, item.size)
    if realAmount <= 0 then return false, "В МЭ-сети нет этого предмета" end
    
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
    return false, "МЭ-сеть отклонила выдачу (0 шт.)"
end

-- Забрать у игрока в МЭ через pim.pushItem + проверка на выпадение в мир
function api.pushFromPlayer(item, amount)
    -- Персональное право: сдача в МЭ
    local playerName = getPimPlayer()
    local denied = checkPermission(playerName, "canDeposit", "сдавать предметы")
    if denied then return false, denied end

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
        return false, "Предмет не найден, либо МЭ-сеть его не приняла"
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
                    return false, "Предмет возвращён в инвентарь: МЭ-сеть его не приняла"
                end
            end
            return false, "Предмет не попал в МЭ-сеть: он остался в ME Interface — заберите его вручную"
        end
    end

    db.addLog(getPimPlayer(), "put", (type(item) == "table" and item.display) or itemLabel, moved)
    if moved >= amount then
        return true, "Сдано: " .. moved .. " шт."
    end
    return false, "МЭ-сеть приняла только " .. moved .. " из " .. amount .. " шт.; остальное осталось в инвентаре"
end

-- Проверка наличия игрока
function api.isPlayerPresent()
    local pim = component.pim
    local ok, name = pcall(function() return pim.getInventoryName() end)
    if not ok then return false end
    return name ~= nil and name ~= ""
end

-- Проверки прав (учитывают и персональные флаги, и глобальные настройки)
function api.canWithdraw(playerName)
    if not playerName then return false end
    return db.canWithdraw(playerName)
end

function api.canDeposit(playerName)
    if not playerName then return false end
    return db.canDeposit(playerName)
end

function api.canCraft(playerName)
    if not playerName then return false end
    return db.canCraft(playerName)
end

-- Информация о крафт-процессорах: всего и занятых.
-- me.getCpus() возвращает список таблиц вида { name, storage, coprocessors, busy }.
-- Если метод недоступен или упал — вернёт нули (без исключений).
function api.getCraftingInfo()
    local result = { totalCpus = 0, busyCpus = 0 }

    local okMe, me = pcall(function() return component.me_interface end)
    if not okMe or not me then return result end

    local okFn, fn = pcall(function() return me.getCpus end)
    if not okFn or fn == nil then return result end

    local ok, cpus = pcall(function() return me.getCpus() end)
    if not ok or type(cpus) ~= "table" then return result end

    for _, cpu in pairs(cpus) do
        result.totalCpus = result.totalCpus + 1
        local busy = nil
        if type(cpu) == "table" then
            busy = cpu.busy
            if busy == nil then busy = cpu.isBusy end
            if type(busy) == "function" then
                local okB, b = pcall(function() return cpu.busy() end)
                if okB then busy = b else busy = nil end
            end
        end
        if busy == true then
            result.busyCpus = result.busyCpus + 1
        end
    end

    return result
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
    
    -- Энергия сети.
    -- В AE2-интеграции OpenComputers методы называются getStoredPower/getMaxStoredPower
    -- (getEnergyStored/getMaxEnergyStored там отсутствуют). Сначала пробуем их у
    -- me_interface, затем у me_controller, а классические имена — как резерв.
    local function readEnergy(source, storedMethod, maxMethod)
        if not source then return nil, nil end
        local okS, stored = pcall(function() return source[storedMethod]() end)
        local okM, maxv = pcall(function() return source[maxMethod]() end)
        if okS and okM and type(stored) == "number" and type(maxv) == "number" and maxv > 0 then
            return stored, maxv
        end
        return nil, nil
    end

    local sources = { me }
    if component.isAvailable("me_controller") then
        sources[#sources + 1] = component.me_controller
    end

    local pairsToTry = {
        { "getStoredPower", "getMaxStoredPower" },
        { "getEnergyStored", "getMaxEnergyStored" },
        { "getEnergy", "getMaxEnergy" },
    }

    for _, source in ipairs(sources) do
        for _, pair in ipairs(pairsToTry) do
            local stored, maxv = readEnergy(source, pair[1], pair[2])
            if stored and maxv then
                info.energyStored = math.floor(stored)
                info.energyMax = math.floor(maxv)
                info.energySource = pair[1] .. "()"
                break
            end
        end
        if info.energyStored then break end
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
--
-- Как это работает:
--   1) Если у me_interface есть getCells()/getDrives() — берём данные оттуда (точно).
--   2) Если нет (типичный OC 1.7.10: в AE2-интеграции таких методов нет) —
--      считаем ЗАНЯТОЕ по формуле AE2: 8 предметов = 1 байт, каждый тип = 8 байт
--      (usedBytes = ceil(кол-во / 8) + типы * 8; сходится: 1k-ячейка = 8128 шт.).
--      Это точное значение занятого, просто без общего объёма.
--   3) Общий объём (ёмкость) можно задать вручную в config.storage.totalBytes —
--      тогда в UI появится реальный процент заполнения.
function api.getStorageInfo()
    local okMe, me = pcall(function() return component.me_interface end)
    if not okMe or not me then return nil end

    local cfg = config.storage or {}

    local acc = { totalBytes = 0, usedBytes = 0, totalTypes = 0, usedTypes = 0 }
    local found = false

    -- 1) Список ячеек сети (если сборка OC это умеет)
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

    -- Ручная ёмкость из config.lua. Если задана — она приоритетнее всего
    -- (и для getCells, и для резервного расчёта): даёт точный процент.
    local manualTotal = tonumber(cfg.totalBytes)
    local manualTypes = tonumber(cfg.totalTypes)
    local hasManual = manualTotal ~= nil and manualTotal > 0

    local result
    if found and (acc.totalBytes > 0 or acc.totalTypes > 0) then
        -- Данные от getCells()/getDrives() — точные
        result = acc
        result.estimated = false
    else
        -- Резерв: метода нет. Занятое считаем по предметам сети.
        local items = api.getNetworkItems()
        if type(items) ~= "table" or #items == 0 then
            if not hasManual then return nil end
            items = {}
        end

        local totalItems = 0
        for _, it in ipairs(items) do
            totalItems = totalItems + (tonumber(it.size) or 0)
        end

        local usedTypes = #items
        result = {
            totalBytes = nil,
            usedBytes = math.ceil(totalItems / 8) + usedTypes * 8,
            totalTypes = nil,
            usedTypes = usedTypes,
            -- true — ёмкость неизвестна, UI покажет только оценку занятого
            estimated = true,
        }
    end

    if hasManual then
        result.totalBytes = manualTotal
        result.estimated = false
    end
    if manualTypes and manualTypes > 0 then
        result.totalTypes = manualTypes
    end

    return result
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
    -- Персональное право: сдача в МЭ
    local playerName = getPimPlayer()
    local denied = checkPermission(playerName, "canDeposit", "сдавать предметы")
    if denied then return 0, denied end

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
        return moved, "Некоторые предметы не попали в МЭ-сеть — заберите их из ME Interface вручную"
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