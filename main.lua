local component = require("component")
local event = require("event")
local unicode = require("unicode")
local gpu = component.gpu
local screen = component.screen

if not component.isAvailable("me_interface") then
    print("Ошибка: ME Interface не найден!")
    os.exit()
end
local me = component.me_interface

-- Палитра цветов
local COLOR_BG = 0x1A1A1A
local COLOR_FG = 0xE0E0E0
local COLOR_BORDER = 0x0055AA
local COLOR_TITLE = 0x00AAFF
local COLOR_BTN = 0x333333
local COLOR_BTN_HOVER = 0x00AA00
local COLOR_WHITE = 0xFFFFFF
local COLOR_STATUS_OK = 0x00AA00
local COLOR_STATUS_ERR = 0xFF5555

-- Переменные для пагинации
local itemList = {}
local currentPage = 1
local itemsPerPage = 15 -- Будет пересчитано ниже
local totalPages = 1

-- 1. ПОЛУЧАЕМ РАЗМЕР ЭКРАНА
gpu.setResolution(gpu.maxResolution()) -- Ставим максимальное доступное разрешение
local W, H = gpu.getResolution()

local function drawFrame(x, y, w, h, color)
    gpu.setForeground(color)
    gpu.set(x, y, "╔" .. string.rep("═", w - 2) .. "╗")
    for i = 1, h - 2 do
        gpu.set(x, y + i, "║")
        gpu.set(x + w - 1, y + i, "║")
    end
    gpu.set(x, y + h - 1, "╚" .. string.rep("═", w - 2) .. "╝")
    gpu.setForeground(COLOR_FG)
end

local function drawButton(x, y, width, text, isPressed)
    if isPressed then
        gpu.setBackground(COLOR_BTN_HOVER)
    else
        gpu.setBackground(COLOR_BTN)
    end
    gpu.fill(x, y, width, 1, " ")
    
    local btnText = "[ " .. text .. " ]"
    local textLen = unicode.len(btnText)
    local textX = x + math.floor((width - textLen) / 2)
    
    gpu.setForeground(COLOR_WHITE)
    if isPressed then
        gpu.set(textX + 1, y, btnText)
    else
        gpu.set(textX, y, btnText)
    end
    
    gpu.setBackground(COLOR_BG)
    gpu.setForeground(COLOR_FG)
end

local function refreshList()
    local rawItems = me.getItemsInNetwork()
    itemList = {}
    for _, item in pairs(rawItems) do
        if item and item.label then
            table.insert(itemList, { label = item.label, size = item.size })
        end
    end
    table.sort(itemList, function(a, b) return a.label < b.label end)
    
    -- Пересчитываем количество страниц
    totalPages = math.max(1, math.ceil(#itemList / itemsPerPage))
    -- Если после обновления мы оказались за пределами страниц, сбрасываем на первую
    if currentPage > totalPages then currentPage = totalPages end
end

local function drawList()
    -- Очищаем область списка (между заголовком и кнопками)
    gpu.setBackground(COLOR_BG)
    gpu.fill(2, 5, W - 3, H - 9, " ")
    
    if #itemList == 0 then
        gpu.setForeground(0x888888)
        gpu.set(3, 6, "МЭ-сеть пуста...")
        return
    end
    
    -- Вычисляем, какие предметы показывать на текущей странице
    local startIdx = (currentPage - 1) * itemsPerPage + 1
    local endIdx = math.min(currentPage * itemsPerPage, #itemList)
    
    local screenRow = 1
    for i = startIdx, endIdx do
        local item = itemList[i]
        local displayLabel = item.label
        
        -- Обрезка под ширину экрана (минус отступы и место под цифры)
        local maxLabelLen = W - 20 
        if unicode.len(displayLabel) > maxLabelLen then
            displayLabel = unicode.sub(displayLabel, 1, maxLabelLen - 3) .. "..."
        end
        
        local paddingCount = maxLabelLen - unicode.len(displayLabel)
        local padding = string.rep(" ", paddingCount)
        
        local line = displayLabel .. padding .. " | " .. string.format("%8d", item.size)
        
        gpu.setForeground(COLOR_FG)
        gpu.set(3, 4 + screenRow, line)
        screenRow = screenRow + 1
    end
    
    -- Выводим информацию о страницах
    gpu.setForeground(0x888888)
    local pageText = "Стр. " .. currentPage .. " из " .. totalPages
    gpu.set(W - unicode.len(pageText) - 3, 2, pageText)
end

-- Кнопки (динамически расположены)
local buttons = {
    {x = 5, y = H - 2, width = 12, text = "<<", action = "prev"},
    {x = 19, y = H - 2, width = 15, text = "ОБНОВИТЬ", action = "refresh"},
    {x = 36, y = H - 2, width = 12, text = ">>", action = "next"},
    {x = W - 20, y = H - 2, width = 15, text = "ВЫХОД", action = "exit"}
}

-- Первичная отрисовка
gpu.setBackground(COLOR_BG)
gpu.setForeground(COLOR_FG)
gpu.fill(1, 1, W, H, " ")

drawFrame(1, 1, W, H, COLOR_BORDER)

gpu.setForeground(COLOR_TITLE)
local title = "--- Содержимое МЭ-сети ---"
gpu.set(math.floor((W - unicode.len(title)) / 2) + 1, 2, title)

-- Рисуем рамку списка
drawFrame(2, 4, W - 3, H - 8, COLOR_BORDER)

-- Считаем, сколько строк помещается в рамку
itemsPerPage = H - 9 

-- Отрисовка кнопок
for _, btn in ipairs(buttons) do
    drawButton(btn.x, btn.y, btn.width, btn.text, false)
end

refreshList()
drawList()

-- Главный цикл
while true do
    local _, _, x, y = event.pull("touch")
    
    for i, btn in ipairs(buttons) do
        if y == btn.y and x >= btn.x and x < btn.x + btn.width then
            
            drawButton(btn.x, btn.y, btn.width, btn.text, true)
            os.sleep(0.1) 
            
            if btn.action == "refresh" then
                currentPage = 1 -- При обновлении сбрасываем на первую страницу
                refreshList()
                drawList()
                gpu.setForeground(COLOR_STATUS_OK)
                gpu.set(3, H - 1, "Статус: Список успешно обновлен!      ")
                
            elseif btn.action == "prev" then
                if currentPage > 1 then
                    currentPage = currentPage - 1
                    drawList()
                end
                
            elseif btn.action == "next" then
                if currentPage < totalPages then
                    currentPage = currentPage + 1
                    drawList()
                end
                
            elseif btn.action == "exit" then
                gpu.setForeground(COLOR_STATUS_ERR)
                gpu.set(3, H - 1, "Статус: Завершение работы...")
                os.sleep(0.5)
                os.exit()
            end
            
            drawButton(btn.x, btn.y, btn.width, btn.text, false)
            gpu.setForeground(COLOR_FG) -- Сбрасываем цвет после статуса
            break 
        end
    end
end
