-- test_craft.lua — диагностика вкладки «Крафт» (ME getCraftables).
-- Запуск:  test_craft.lua
-- Выводит в консоль: есть ли метод, ошибки, длину списка и структуру первых 3 рецептов.

local component = require("component")

local function line(text)
    print(tostring(text or ""))
end

local function rule(char)
    line(string.rep(char or "-", 60))
end

local function safe(fn, ...)
    local ok, res = pcall(fn, ...)
    if ok then return true, res end
    local msg = tostring(res)
    -- Убираем "путь:строка: " из текста ошибки
    local short = msg:match("^.-[\\/][^\\/]-:%d+:%s*(.+)$")
    if not short then short = msg:match("^.-:%d+:%s*(.+)$") end
    return false, short or msg
end

local function field(v)
    if v == nil then return "nil" end
    return tostring(v)
end

rule("=")
line("ДИАГНОСТИКА КРАФТОВ (ME getCraftables)")
rule("=")

-- 1. Компонент me_interface
if not component.isAvailable("me_interface") then
    line("[FAIL] Компонент me_interface не найден.")
    line("       Проверьте, что компьютер подключён к ME Interface / ME Controller.")
    return
end
line("[OK]   Компонент me_interface найден: " .. tostring(component.me_interface.address))
line("")

local me = component.me_interface

-- 2. Что вообще лежит в me.getCraftables (без проверки type == "function")
local okGet, getCraftables = safe(function() return me.getCraftables end)
if not okGet then
    line("[FAIL] Не удалось прочитать me.getCraftables: " .. tostring(getCraftables))
    return
end

line("me.getCraftables:")
line("    type          = " .. type(getCraftables))

local okMt, mt = safe(getmetatable, getCraftables)
if not okMt then
    line("    getmetatable  = ОШИБКА -> " .. tostring(mt))
else
    line("    getmetatable  = " .. tostring(mt))
    if type(mt) == "table" then
        line("    __call        = " .. type(mt.__call))
        line("    __index       = " .. type(mt.__index))
        if mt.__call ~= nil then
            line("    Вызываемый объект (есть __call) — прямой вызов должен работать.")
        end
    end
end

if getCraftables == nil then
    line("[FAIL] me.getCraftables == nil: метод отсутствует в этой сборке OC/AE2.")
    line("       Список рецептов недоступен, крафтить через панель нельзя.")
    return
end
line("")

-- 3. Пробуем вызвать me.getCraftables() — именно с круглыми скобками
line("Вызов me.getCraftables() ...")
local okCall, craftables = safe(function() return me.getCraftables() end)
if not okCall then
    line("[FAIL] Вызов упал с ошибкой: " .. tostring(craftables))
    -- Подсказка, если объект не вызывается вообще
    local okMt2, mt2 = safe(getmetatable, getCraftables)
    if okMt2 and type(mt2) == "table" and mt2.__call then
        line("       У объекта есть __call, но прямой вызов не сработал.")
    elseif type(getCraftables) ~= "function" then
        line("       Объект не является функцией и не имеет __call — вызвать нельзя.")
    end
    return
end
line("[OK]   Вызов успешен")
line("Тип результата: " .. type(craftables))

if type(craftables) ~= "table" then
    line("[FAIL] Ожидалась table, получено: " .. type(craftables))
    return
end

local count = #craftables
line("Длина списка (#craftables): " .. tostring(count))

-- Дополнительно: число пар (на случай не-массива)
local pairsCount = 0
for _ in pairs(craftables) do pairsCount = pairsCount + 1 end
if pairsCount ~= count then
    line("Пар в таблице (pairs): " .. tostring(pairsCount) .. "  (таблица не является чистым массивом)")
end

if count == 0 then
    line("")
    line("[WARN] Список пуст: в МЭ нет известных рецептов.")
    return
end
line("")

-- 4. Структура первых 3 элементов
rule("-")
line("Первые " .. math.min(3, count) .. " рецепта:")
rule("-")

for i = 1, math.min(3, count) do
    local item = craftables[i]
    line("[" .. i .. "] объект: " .. type(item))

    if type(item) ~= "table" and type(item) ~= "userdata" then
        line("    (не таблица и не userdata — пропуск)")
    else
        local okStack, stack = safe(function() return item.getItemStack() end)
        if not okStack then
            line("    getItemStack(): ОШИБКА -> " .. tostring(stack))
        elseif type(stack) ~= "table" then
            line("    getItemStack() вернул " .. type(stack) .. " вместо table")
        else
            line("    name   = " .. field(stack.name))
            line("    label  = " .. field(stack.label or stack.display_name))
            line("    damage = " .. field(stack.damage))
            line("    size   = " .. field(stack.size))

            -- Список полей, чтобы увидеть неожиданные варианты структуры
            local keys = {}
            for k in pairs(stack) do keys[#keys + 1] = tostring(k) end
            table.sort(keys)
            line("    поля   = " .. table.concat(keys, ", "))
        end

        -- Проверка метода request без отправки запроса
        line("    request= " .. type(item.request))
    end
    line("")
end

-- 5. Сводка
rule("=")
line("ИТОГ: рецептов " .. tostring(count))

-- Быстрая проверка первого элемента через api (если модуль рядом)
local okApi, api = pcall(require, "me_api")
if okApi and type(api) == "table" and type(api.getCraftables) == "function" then
    local list = api.getCraftables()
    line("api.getCraftables(): " .. tostring(#list) .. " шт.")
    if #list == 0 and _G.last_craft_error then
        line("_G.last_craft_error: " .. tostring(_G.last_craft_error))
    elseif #list > 0 then
        local first = list[1]
        line("Первый: " .. tostring(first.display or first.label) ..
             " | name=" .. field(first.name) .. " | damage=" .. field(first.damage))
    end
else
    line("(me_api.lua не найден рядом — проверка через api пропущена)")
end
rule("=")
