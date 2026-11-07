local component = require("component")
local event = require("event")
local unicode = require("unicode")
local gpu = component.gpu

local config = require("config")
local ui = require("ui")
local api = require("me_api")
local db = require("db")

if not component.isAvailable("me_interface") or not component.isAvailable("pim") then
    print("Ошибка: ME Interface или PIM не найден!") os.exit()
end

db.load()
gpu.setResolution(gpu.maxResolution())
local W, H = gpu.getResolution()

local state = {
    items = {}, page = 1, totalPages = 1, selectedItem = nil, quantity = 1,
    currentTab = "ME", player = nil, isAdmin = false, adminList = {},
    statusMsg = "", statusErr = false
}

local function setStatus(msg, isError)
    state.statusMsg = msg
    state.statusErr = isError
    -- Мгновенная отрисовка статуса (если drawScreen не будет вызван сразу)
    gpu.setBackground(config.colors.bg)
    gpu.fill(1, H - 1, W, 1, " ")
    gpu.setForeground(isError and config.colors.err or config.colors.ok)
    gpu.set(3, H - 1, msg)
end

local function updateList()
    if state.currentTab == "ME" then
        state.items = api.getNetworkItems()
    elseif state.currentTab == "INV" then
        state.items = api.getPlayerInventory()
    elseif state.currentTab == "ADMIN" then
        -- Конвертируем таблицу в сортированный массив для стабильного отображения
        local raw = db.getAllPlayers()
        state.adminList = {}
        for name, data in pairs(raw) do
            table.insert(state.adminList, {name = name, data = data})
        end
        table.sort(state.adminList, function(a, b) return a.name < b.name end)
    end
    
    if state.currentTab ~= "ADMIN" then
        state.totalPages = math.max(1, math.ceil(#state.items / (H - 10)))
        if state.page > state.totalPages then state.page = state.totalPages end
    end
end

local function drawScreen()
    ui.drawMain(W, H, state)
    -- После отрисовки основного экрана принудительно рисуем статус, чтобы он не исчез
    gpu.setBackground(config.colors.bg)
    gpu.fill(1, H - 1, W, 1, " ")
    gpu.setForeground(state.statusErr and config.colors.err or config.colors.ok)
    gpu.set(3, H - 1, state.statusMsg)
end

updateList(); drawScreen()

while true do
    -- ИСПРАВЛЕНИЕ 1: Добавлена 4-я переменная p3 для правильного захвата координат клика
    local eventName, p1, p2, p3 = event.pull("touch", "player_on", "player_off")
    
    if eventName == "player_on" then
        state.player = tostring(p1)
        local pData = db.getPlayer(state.player)
        
        if not pData then
            db.registerPlayer(state.player)
            pData = db.getPlayer(state.player)
            setStatus("Новый игрок: " .. state.player)
        else
            setStatus("С возвращением, " .. state.player)
        end
        
        state.isAdmin = (pData.role == "admin")
        if state.isAdmin then setStatus("Вы вошли как Админ.") end
        
        state.currentTab = "ME"
        updateList(); drawScreen()
        
    elseif eventName == "player_off" then
        state.player = nil
        state.isAdmin = false
        state.currentTab = "ME"
        state.selectedItem = nil -- ИСПРАВЛЕНИЕ 4: Закрываем открытую карточку при уходе
        state.page = 1
        setStatus("Игрок ушел с PIM.", true)
        updateList(); drawScreen()
        
    elseif eventName == "touch" then
        -- ИСПРАВЛЕНИЕ 1: Для touch p2 - это X, p3 - это Y
        local x, y = p2, p3
        
        -- Переключение вкладок
        if y == 2 then
            local t1, t2, t3 = " МЭ-сеть ", " Инвентарь ", " Админ "
            local totalW = unicode.len(t1) + unicode.len(t2) + 4
            if state.isAdmin then totalW = totalW + unicode.len(t3) + 2 end
            local startX = math.floor((W - totalW) / 2) + 1
            
            local newTab = state.currentTab
            if x >= startX and x < startX + unicode.len(t1) then
                newTab = "ME"
            elseif x >= startX + unicode.len(t1) + 2 and x < startX + unicode.len(t1) + unicode.len(t2) + 2 then
                newTab = "INV"
            elseif state.isAdmin and x >= startX + unicode.len(t1) + unicode.len(t2) + 4 and x < startX + totalW then
                newTab = "ADMIN"
            end
            
            -- ИСПРАВЛЕНИЕ 5: Реагируем только если вкладка реально изменилась
            if newTab ~= state.currentTab then
                state.currentTab = newTab
                state.page = 1; state.selectedItem = nil
                updateList(); drawScreen()
            end
            
        elseif state.currentTab == "ADMIN" and state.isAdmin then
            -- Клик по списку игроков в админке
            local row = y - 5
            if row >= 1 and state.adminList[row] then -- ИСПРАВЛЕНИЕ 3: Используем отсортированный массив
                local targetName = state.adminList[row].name
                local targetData = state.adminList[row].data
                
                local newRole = "user"
                if targetData.role == "user" then newRole = "admin"
                elseif targetData.role == "admin" then newRole = "banned" end
                
                db.setRole(targetName, newRole)
                setStatus("Роль " .. targetName .. " изменена на " .. newRole)
                updateList(); drawScreen()
            end
            
        elseif state.selectedItem then
            local mw, mh = 56, 16
            local mx, my = math.floor((W - mw) / 2) + 1, math.floor((H - mh) / 2) + 1
            
            -- Кнопки количества
            if y == my + 9 then
                local old = state.quantity
                if x >= mx + 2 and x < mx + 8 then state.quantity = math.max(1, state.quantity - 10) end
                if x >= mx + 9 and x < mx + 15 then state.quantity = math.max(1, state.quantity - 1) end
                if x >= mx + 29 and x < mx + 35 then state.quantity = math.min(state.selectedItem.size, state.quantity + 1) end
                if x >= mx + 36 and x < mx + 42 then state.quantity = math.min(state.selectedItem.size, state.quantity + 10) end
                if old ~= state.quantity then 
                    local canAct = (state.currentTab == "ME" and api.canWithdraw(state.player)) or (state.currentTab == "INV" and api.canDeposit(state.player))
                    ui.drawModal(W, H, state.selectedItem, state.quantity, state.currentTab, canAct) 
                end
            end
            
            -- Кнопка действия
            if y == my + mh - 2 and x >= mx + 2 and x < mx + 20 then
                if not state.player then
                    setStatus("Ошибка: на PIM никого нет!", true)
                elseif state.currentTab == "ME" and not api.canWithdraw(state.player) then
                    setStatus("Вам запрещено забирать предметы!", true)
                elseif state.currentTab == "INV" and not api.canDeposit(state.player) then
                    setStatus("Вам запрещено сдавать предметы!", true)
                else
                    local ok, msg
                    if state.currentTab == "ME" then
                        ok, msg = api.exportToPlayer(state.selectedItem, state.quantity)
                    else
                        ok, msg = api.pushFromPlayer(state.selectedItem.label, state.quantity)
                    end
                    setStatus(msg, not ok)
                end
                os.sleep(1.5); state.selectedItem = nil; updateList(); drawScreen()
            end
            
            -- Закрыть
            if y == my + mh - 2 and x >= mx + mw - 14 and x < mx + mw - 2 then
                state.selectedItem = nil; drawScreen()
            end
            
        else
            -- Навигация и список
            local clicked = false
            if y == H - 2 then
                if x >= 5 and x < 17 then clicked = true; if state.page > 1 then state.page = state.page - 1; drawScreen() end end
                if x >= 19 and x < 34 then clicked = true; updateList(); drawScreen(); setStatus("Обновлено.") end
                if x >= 36 and x < 48 then clicked = true; if state.page < state.totalPages then state.page = state.page + 1; drawScreen() end end
                if x >= W - 20 and x < W - 5 then setStatus("Выход...", true); os.sleep(0.5); os.exit() end
            end
            
            if not clicked and y >= 5 and y <= H - 5 and x >= 3 and x <= W - 3 then
                local idx = (state.page - 1) * (H - 10) + (y - 4)
                if state.items[idx] then 
                    state.selectedItem = state.items[idx]
                    state.quantity = 1
                    local canAct = (state.currentTab == "ME" and api.canWithdraw(state.player)) or (state.currentTab == "INV" and api.canDeposit(state.player))
                    ui.drawModal(W, H, state.selectedItem, state.quantity, state.currentTab, canAct) 
                end
            end
        end
    end
end
