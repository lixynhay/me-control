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
local COLOR_MODAL_BG = 0x2A2A2A -- Фон модального окна

local itemList = {}
local currentPage = 1
local itemsPerPage = 15
local totalPages = 1
local selectedItem = nil -- Храним выбранный предмет (если nil, показываем список)

gpu.setResolution(gpu.maxResolution())
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

local function drawButton(x, y, width, text, isPressed, customBg)
    if isPressed then
        gpu.setBackground(COLOR_BTN_HOVER)
    else
        gpu.setBackground(customBg or COLOR_BTN)
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
    totalPages = math.max(1, math.ceil(#itemList / itemsPerPage))
    if currentPage > totalPages then currentPage = totalPages end
end

local function drawList()
    -- Очищаем область списка
    gpu.setBackground(COLOR_BG)
    gpu.fill(2, 5, W - 3, H - 9, " ")
    
    if #itemList == 0 then
        gpu.setForeground(0x888888)
        gpu.set(3, 6, "МЭ-сеть пуста...")
        return
    end
    
    local startIdx = (currentPage - 1) * itemsPerPage + 1
    local endIdx = math.min(currentPage * itemsPerPage, #itemList)
    
    local screenRow = 1
    for i = startIdx, endIdx do
        local item = itemList[i]
        local displayLabel = item.label
        
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
    
    gpu.setForeground(0x888888)
    local pageText = "Стр. " .. currentPage .. " из " .. totalPages
    gpu.set(W - unicode.len(pageText) - 3, 2, pageText)
end

-- ФУНКЦИЯ ОТРИСОВКИ КАРТОЧКИ ТОВАРА
local function drawModal()
    -- Затемняем фон (рисуем прямоугольник поверх всего)
    gpu.setBackground(0x000000)
    gpu.fill(1, 1, W, H, " ") -- Простая имитация затемнения
    
    local mw, mh = 50, 15 -- Размер окна
    local mx = math.floor((W - mw) / 2) + 1
    local my = math.floor((H - mh) / 2) + 1
    
    gpu.setBackground(COLOR_MODAL_BG)
    gpu.fill(mx, my, mw, mh, " ")
    
    drawFrame(mx, my, mw, mh, COLOR_TITLE)
    
    -- Заголовок окна
    local title = "Информация о предмете"
    gpu.setForeground(COLOR_TITLE)
    gpu.set(mx + math.floor((mw - unicode.len(title)) / 2), my, title)
    
    -- Данные предмета
    gpu.setForeground(COLOR_WHITE)
    gpu.set(mx + 2, my + 2, "Название:")
    gpu.setForeground(COLOR_FG)
    
    local name = selectedItem.label
    if unicode.len(name) > mw - 4 then
        name = unicode.sub(name, 1, mw - 7) .. "..."
    end
    gpu.set(mx + 2, my + 3, name)
    
    gpu.setForeground(COLOR_WHITE)
    gpu.set(mx + 2, my + 5, "В сети:")
    gpu.setForeground(0x00AA00) -- Зеленый для количества
    gpu.set(mx + 2, my + 6, tostring(selectedItem.size) .. " шт.")
    
    -- Кнопки в модальном окне (пока заглушки)
    gpu.setForeground(0x888888)
    gpu.set(mx + 2, my + 9, "(Здесь будут кнопки покупки/продажи)")
    
    -- Кнопка закрытия
    drawButton(mx + mw - 14, my + mh - 2, 12, "ЗАКРЫТЬ", false, 0xAA0000)
end

-- Основные кнопки
local buttons = {
    {x = 5, y = H - 2, width = 12, text = "<<", action = "prev"},
    {x = 19, y = H - 2, width = 15, text = "ОБНОВИТЬ", action = "refresh"},
    {x = 36, y = H - 2, width = 12, text = ">>", action = "next"},
    {x = W - 20, y = H - 2, width = 15, text = "ВЫХОД", action = "exit"}
}

local function drawMainScreen()
    gpu.setBackground(COLOR_BG)
    gpu.setForeground(COLOR_FG)
    gpu.fill(1, 1, W, H, " ")
    
    drawFrame(1, 1, W, H, COLOR_BORDER)
    
    gpu.setForeground(COLOR_TITLE)
    local title = "--- Содержимое МЭ-сети ---"
    gpu.set(math.floor((W - unicode.len(title)) / 2) + 1, 2, title)
    
    drawFrame(2, 4, W - 3, H - 8, COLOR_BORDER)
    
    for _, btn in ipairs(buttons) do
        drawButton(btn.x, btn.y, btn.width, btn.text, false)
    end
    
    drawList()
end

-- Первичная отрисовка
itemsPerPage = H - 9
refreshList()
drawMainScreen()

-- Главный цикл
while true do
    local _, _, x, y = event.pull("touch")
    
    if selectedItem then
        -- ЛОГИКА ДЛЯ ОТКРЫТОГО ОКНА
        local mw, mh = 50, 15
        local mx = math.floor((W - mw) / 2) + 1
        local my = math.floor((H - mh) / 2) + 1
        
        -- Проверка клика по кнопке "Закрыть"
        if y == my + mh - 2 and x >= mx + mw - 14 and x < mx + mw - 2 then
            selectedItem = nil
            drawMainScreen() -- Возвращаемся к списку
        end
    else
        -- ЛОГИКА ДЛЯ ОСНОВНОГО ЭКРАНА
        local clickedButton = false
        
        -- Проверяем кнопки навигации
        for i, btn in ipairs(buttons) do
            if y == btn.y and x >= btn.x and x < btn.x + btn.width then
                clickedButton = true
                drawButton(btn.x, btn.y, btn.width, btn.text, true)
                os.sleep(0.1) 
                
                if btn.action == "refresh" then
                    currentPage = 1
                    refreshList()
                    drawMainScreen()
                elseif btn.action == "prev" and currentPage > 1 then
                    currentPage = currentPage - 1
                    drawMainScreen()
                elseif btn.action == "next" and currentPage < totalPages then
                    currentPage = currentPage + 1
                    drawMainScreen()
                elseif btn.action == "exit" then
                    gpu.setForeground(COLOR_STATUS_ERR)
                    gpu.set(3, H - 1, "Статус: Завершение работы...")
                    os.sleep(0.5)
                    os.exit()
                end
                break 
            end
        end
        
        -- Проверяем, не кликнули ли мы по списку предметов
        if not clickedButton then
            -- Клик внутри области списка?
            if y >= 5 and y <= H - 5 and x >= 3 and x <= W - 3 then
                -- Вычисляем, на какую строку пришелся клик
                local clickedRow = y - 4
                local startIdx = (currentPage - 1) * itemsPerPage
                local itemIndex = startIdx + clickedRow
                
                -- Если кликнули на существующий предмет
                if itemIndex <= #itemList then
                    selectedItem = itemList[itemIndex]
                    drawModal() -- Показываем карточку
                end
            end
        end
    end
end
