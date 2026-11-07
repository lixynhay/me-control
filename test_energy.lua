-- test_energy.lua — диагностика источников энергии в МЭ-сети (AE2 + OpenComputers).
-- Запуск:  test_energy.lua
--
-- Проверяет:
--   1. Какие энергетические компоненты доступны компьютеру.
--   2. Какие у них есть методы (фильтр по energy/power/store/get/max/storage/capacity).
--   3. Типовые методы получения энергии (через pcall).
--   4. Все компоненты с me_/ae_/energy/power в типе и их методы.
--   5. Итог: сколько энергии в сети и какой метод сработал.

local component = require("component")

-- ==================== утилиты ====================

local function line(text)
    print(tostring(text or ""))
end

local function rule(ch)
    line(string.rep(ch or "-", 58))
end

-- Чистит текст ошибки Lua: убирает путь к файлу и номер строки
local function cleanError(err)
    local msg = tostring(err or "неизвестная ошибка")
    local short = msg:match("^.-[\\/][^\\/]-:%d+:%s*(.+)$")
    if not short then short = msg:match("^.-:%d+:%s*(.+)$") end
    return short or msg
end

-- Короткое представление значения (без гигантских таблиц)
local function fmtValue(v)
    local t = type(v)
    if t == "number" then
        if v == math.floor(v) and math.abs(v) < 1e15 then
            return tostring(math.floor(v))
        end
        return string.format("%.3f", v)
    elseif t == "boolean" then
        return tostring(v)
    elseif t == "nil" then
        return "nil"
    elseif t == "string" then
        if #v > 40 then return '"' .. v:sub(1, 37) .. '..."' end
        return '"' .. v .. '"'
    elseif t == "table" then
        local n = 0
        for _ in pairs(v) do n = n + 1 end
        return "table(" .. n .. ")"
    end
    return t
end

-- Безопасная обрезка UTF-8 строки до maxBytes (не рвёт многобайтовый символ)
local function truncateUtf8(s, maxBytes)
    s = tostring(s)
    if #s <= maxBytes then return s end
    local cut = maxBytes
    -- отступаем назад, пока не выйдем на стартовый байт символа
    while cut > 1 do
        local b = s:byte(cut + 1)
        if not b or b < 0x80 or b >= 0xC0 then break end
        cut = cut - 1
    end
    return s:sub(1, cut) .. "..."
end

-- Безопасно берёт прокси компонента по адресу
local function getProxy(address)
    local ok, proxy = pcall(function() return component.proxy(address) end)
    if ok and proxy ~= nil then return proxy end
    return nil
end

-- Безопасно получает список методов компонента
local function getMethods(address)
    local ok, methods = pcall(function() return component.methods(address) end)
    if not ok or type(methods) ~= "table" then return nil, tostring(methods) end
    return methods
end

-- Список частей названия метода, которые нас интересуют
local INTERESTING = { "energy", "power", "store", "storage", "capacity", "max", "get" }

local function isInterestingMethod(name)
    local lower = string.lower(tostring(name))
    for _, part in ipairs(INTERESTING) do
        if lower:find(part, 1, true) then return true end
    end
    return false
end

-- Вызывает метод компонента и печатает результат
-- Возвращает: true, значение | false, текст ошибки
local function tryMethod(proxy, method, indent)
    indent = indent or "    "

    -- Сначала проверяем, существует ли метод вообще
    local okRef, fn = pcall(function() return proxy[method] end)
    if not okRef then
        local err = cleanError(fn)
        line(indent .. "[FAIL] " .. method .. "() -> " .. err)
        return false, err
    end
    if fn == nil then
        line(indent .. "[FAIL] " .. method .. "() -> метод отсутствует")
        return false, "метод отсутствует"
    end

    local ok, result = pcall(function() return proxy[method]() end)
    if ok then
        line(indent .. "[OK] " .. method .. "() -> " .. fmtValue(result))
        return true, result
    end
    local err = cleanError(result)
    line(indent .. "[FAIL] " .. method .. "() -> " .. err)
    return false, err
end

-- ==================== БЛОК 1 ====================

rule("=")
line("ДИАГНОСТИКА ЭНЕРГИИ МЭ-СЕТИ")
rule("=")
line("")

line("[1] ПОИСК ЭНЕРГЕТИЧЕСКИХ КОМПОНЕНТОВ")
rule("-")

local candidates = {
    "me_controller",
    "energy_acceptor",
    "me_interface",
    "me_energy_cell",
    "energy_cell",
    "capacitor_bank",
}

local found = {}   -- { {name=..., address=..., proxy=...}, ... }

for _, name in ipairs(candidates) do
    local okAvail, available = pcall(function() return component.isAvailable(name) end)
    if okAvail and available then
        local okComp, proxy = pcall(function() return component[name] end)
        local address = "?"
        if okComp and proxy ~= nil then
            local okAddr, addr = pcall(function() return proxy.address end)
            if okAddr and addr then address = tostring(addr) end
        end
        line("[OK] Найден компонент: " .. name .. " (адрес: " .. address .. ")")
        found[#found + 1] = { name = name, address = address, proxy = okComp and proxy or nil }
    else
        line("[--] Нет компонента: " .. name)
    end
end

if #found == 0 then
    line("")
    line("Энергетических компонентов не найдено.")
end
line("")

-- ==================== БЛОК 2 ====================

line("[2] МЕТОДЫ НАЙДЕННЫХ КОМПОНЕНТОВ")
rule("-")

local methodsByAddress = {}

if #found == 0 then
    line("(нет компонентов для опроса)")
    line("")
else
    for _, comp in ipairs(found) do
        line("--- " .. comp.name .. " (" .. comp.address .. ") ---")

        local methods, mErr = getMethods(comp.address)
        if not methods then
            line("    [FAIL] component.methods(): " .. cleanError(mErr))
        else
            methodsByAddress[comp.address] = methods

            -- Собираем и сортируем все методы
            local all = {}
            for name in pairs(methods) do all[#all + 1] = tostring(name) end
            table.sort(all)

            line("    всего методов: " .. #all)

            local interesting = {}
            for _, name in ipairs(all) do
                if isInterestingMethod(name) then interesting[#interesting + 1] = name end
            end

            if #interesting == 0 then
                line("    подходящих методов нет")
            else
                line("    подходящие методы:")
                for _, name in ipairs(interesting) do
                    local doc = methods[name]
                    if type(doc) == "string" and doc ~= "" then
                        doc = doc:gsub("%s+", " ")
                        line("      - " .. name .. "  (" .. truncateUtf8(doc, 46) .. ")")
                    else
                        line("      - " .. name)
                    end
                end
            end
        end
        line("")
    end
end

-- ==================== БЛОК 3 ====================

line("[3] ТИПОВЫЕ МЕТОДЫ (через pcall)")
rule("-")

if #found == 0 then
    line("(нет компонентов для опроса)")
    line("")
end

-- Пары «занято / всего» для подсчёта итога
local PAIRS = {
    { stored = "getEnergyStored",     max = "getMaxEnergyStored" },
    { stored = "getStoredPower",      max = "getMaxStoredPower" },
    { stored = "getEnergy",           max = "getMaxEnergy" },
}

-- Методы, которые просто показываем (без пары)
local EXTRA_METHODS = {
    "getAverageInsertion",
    "getAverageExtraction",
    "getAvgPowerInjection",
    "getAvgPowerUsage",
    "getIdlePowerUsage",
}

local best = nil   -- { source, stored, max }

for _, comp in ipairs(found) do
    line("--- " .. comp.name .. " (" .. comp.address .. ") ---")

    local proxy = comp.proxy or getProxy(comp.address)
    if not proxy then
        line("    [FAIL] прокси недоступен")
    else
        local got = {}

        -- Пары «занято / всего»
        for _, pair in ipairs(PAIRS) do
            local okS, stored = tryMethod(proxy, pair.stored)
            if okS and type(stored) == "number" then
                local okM, maxv = tryMethod(proxy, pair.max)
                if okM and type(maxv) == "number" and maxv > 0 and stored <= maxv then
                    if not best then
                        best = {
                            source = comp.name .. " (" .. comp.address .. ")",
                            stored = stored,
                            max = maxv,
                            storedMethod = pair.stored,
                            maxMethod = pair.max,
                        }
                    end
                    got[#got + 1] = pair.stored .. " / " .. pair.max
                end
            end
        end

        -- Прочие полезные методы
        for _, method in ipairs(EXTRA_METHODS) do
            tryMethod(proxy, method)
        end

        if #got == 0 then
            line("    (пары «занято/всего» не найдены)")
        end
    end
    line("")
end

-- ==================== БЛОК 4 ====================

line("[4] ВСЕ КОМПОНЕНТЫ С me_/ae_/energy/power")
rule("-")

local KEYWORDS = { "me_", "ae_", "energy", "power" }
local seen = {}
local listedCount = 0
local meCount = 0

local okList, listErr = pcall(function()
    for address, ctype in component.list() do
        listedCount = listedCount + 1
        local lower = string.lower(tostring(ctype))
        local matched = false
        for _, kw in ipairs(KEYWORDS) do
            if lower:find(kw, 1, true) then matched = true; break end
        end

        if matched and not seen[address] then
            seen[address] = true
            meCount = meCount + 1

            local methods = methodsByAddress[address]
            if not methods then
                methods = getMethods(address)
            end

            line(string.format("%-16s %s", tostring(ctype), tostring(address)))
            if type(methods) == "table" then
                local names = {}
                for name in pairs(methods) do names[#names + 1] = tostring(name) end
                table.sort(names)
                if #names == 0 then
                    line("    (методов нет)")
                else
                    -- Печатаем в несколько колонок, чтобы влезло в консоль
                    local buf = "    "
                    for i, name in ipairs(names) do
                        local piece = name .. (i < #names and ", " or "")
                        if #buf + #piece > 56 then
                            line(buf)
                            buf = "    " .. piece
                        else
                            buf = buf .. piece
                        end
                    end
                    if buf:match("%S") then line(buf) end
                end
            else
                line("    [FAIL] component.methods(): " .. cleanError(methods))
            end
            line("")
        end
    end
end)

if not okList then
    line("[FAIL] component.list(): " .. cleanError(listErr))
else
    line("всего компонентов: " .. listedCount .. " | подходящих: " .. meCount)
end
line("")

-- ==================== БЛОК 5 ====================

rule("=")
if best then
    local stored = math.floor(tonumber(best.stored) or 0)
    local maxv = math.floor(tonumber(best.max) or 0)
    local pct = 0
    if maxv > 0 then
        pct = math.floor(stored / maxv * 100 + 0.5)
    end
    line(string.format("ИТОГ: Энергия = %.0f / %.0f (%.0f%%)", stored, maxv, pct))
    line("Источник: " .. best.source)
    line("Методы:   " .. best.storedMethod .. "() / " .. best.maxMethod .. "()")
else
    line("ИТОГ: Методы получения энергии не найдены.")
    line("Требуется установка адаптера вплотную к ME Controller.")
end
rule("=")
