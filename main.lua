-- Сброс кэша модулей проекта: обновления через getcode подхватываются без перезагрузки
package.loaded["ui"] = nil
package.loaded["me_api"] = nil
package.loaded["db"] = nil
package.loaded["config"] = nil

local component = require("component")
local event = require("event")
local unicode = require("unicode")
local computer = require("computer")
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

-- Принудительный инвертированный режим касания: прямой клик ПКМ = событие touch
local screen = component.screen
screen.setTouchModeInverted(true)

local W, H = gpu.getResolution()

local state = {
    items = {}, page = 1, totalPages = 1, selectedItem = nil, quantity = 1,
    currentTab = "ME", player = nil, isAdmin = false, adminList = {},
    statusMsg = "", statusErr = false,
    networkInfo = {},
    monitorStatus = {},
    lastUpdate = 0
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
        if api.isPlayerPresent() then
            state.items = api.getPlayerInventory()
        else
            state.items = {}
        end
    elseif state.currentTab == "ADMIN" then
        -- Конвертируем таблицу в сортированный массив для стабильного отображения
        local raw = db.getAllPlayers()
        state.adminList = {}
        for name, data in pairs(raw) do
            table.insert(state.adminList, {name = name, data = data})
        end
        table.sort(state.adminList, function(a, b) return a.name < b.name end)
    elseif state.currentTab == "STATS" then
        state.items = {}
        state.networkInfo = api.getNetworkInfo()
    elseif state.currentTab == "MON" then
        state.items = {}
        state.monitorStatus = api.getThresholdStatus()
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

local initialPlayer = component.pim.getInventoryName()
if initialPlayer and initialPlayer ~= "" then
    state.player = initialPlayer
    local pData = db.getPlayer(state.player)
    if pData then
        state.isAdmin = (pData.role == "admin")
    end
end

updateList(); drawScreen()

local success, err = pcall(function()
while true do
    -- Ловим все события; фильтрация выполняется ниже по eventName
    local eventName, p1, p2, p3 = event.pull(0.1)
    if eventName == "interrupted" then break end
    
    -- Автообновление статистики и монитора раз в 2 секунды (не трогаем открытую карточку)
    if state.selectedItem == nil and (state.currentTab == "STATS" or state.currentTab == "MON") and computer.uptime() - state.lastUpdate > 2 then
        updateList()
        drawScreen()
        state.lastUpdate = computer.uptime()
    end
    
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
            local layout = ui.getTabLayout(W, state.isAdmin)
            local newTab = state.currentTab
            
            for _, tab in ipairs(layout) do
                if x >= tab.x and x < tab.x + tab.w then
                    newTab = tab.id
                    break
                end
            end
            
            if newTab ~= state.currentTab then
                state.currentTab = newTab
                state.page = 1; state.selectedItem = nil
                updateList(); drawScreen()
            end
            
        elseif not state.selectedItem and y == H - 2 then
            -- Нижняя панель: работает на всех вкладках (раскладка общая с ui)
            local bottom = ui.getBottomLayout(W)
            if x >= bottom.prev.x and x < bottom.prev.x + bottom.prev.w then if state.page > 1 then state.page = state.page - 1; drawScreen() end end
            if x >= bottom.refresh.x and x < bottom.refresh.x + bottom.refresh.w then state.lastUpdate = 0; updateList(); drawScreen(); setStatus("Обновлено.") end
            if x >= bottom.next.x and x < bottom.next.x + bottom.next.w then if state.page < state.totalPages then state.page = state.page + 1; drawScreen() end end
            if state.currentTab == "INV" and bottom.deposit and x >= bottom.deposit.x and x < bottom.deposit.x + bottom.deposit.w then
                if not api.isPlayerPresent() then
                    setStatus("Встаньте на PIM для сдачи!", true)
                elseif not api.canDeposit(state.player) then
                    setStatus("Вам запрещено сдавать предметы!", true)
                else
                    local moved, msg = api.depositAll()
                    updateList(); drawScreen()
                    setStatus(msg, moved == 0)
                end
            end
            if x >= bottom.exit.x and x < bottom.exit.x + bottom.exit.w then setStatus("Выход...", true); os.sleep(0.5); break end
            
        elseif state.currentTab == "ADMIN" and state.isAdmin then
            -- Клик по списку игроков в админке (только по строкам списка, не по нижней панели)
            local row = y - 5
            if y >= 6 and y <= H - 3 and row >= 1 and state.adminList[row] then -- ИСПРАВЛЕНИЕ 3: Используем отсортированный массив
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
                    ui.drawModal(W, H, state.selectedItem, state.quantity, state.currentTab, canAct, state.isAdmin) 
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
            
            -- Кнопка лимита (только админ): цикл 100 -> 1000 -> 10000 -> 100000 -> Нет
            if state.isAdmin and y == my + mh - 3 and x >= mx + mw - 20 and x < mx + mw - 2 then
                local thresholds = db.getThresholds()
                local cur = thresholds[state.selectedItem.name]
                local curMin = cur and cur.min or nil
                local newMin
                if curMin == nil then newMin = 100
                elseif curMin == 100 then newMin = 1000
                elseif curMin == 1000 then newMin = 10000
                elseif curMin == 10000 then newMin = 100000
                else newMin = 0 end
                
                db.setThreshold(state.selectedItem.name, state.selectedItem.label, newMin)
                local canAct = (state.currentTab == "ME" and api.canWithdraw(state.player)) or (state.currentTab == "INV" and api.canDeposit(state.player))
                ui.drawModal(W, H, state.selectedItem, state.quantity, state.currentTab, canAct, state.isAdmin)
            end
            
        else
            -- Клик по списку (навигация уже обработана выше)
            if y >= 5 and y <= H - 6 and x >= 3 and x <= W - 3 then
                local idx = (state.page - 1) * (H - 10) + (y - 4)
                if (state.currentTab == "ME" or state.currentTab == "INV") and state.items[idx] then 
                    state.selectedItem = state.items[idx]
                    state.quantity = 1
                    local canAct = (state.currentTab == "ME" and api.canWithdraw(state.player)) or (state.currentTab == "INV" and api.canDeposit(state.player))
                    ui.drawModal(W, H, state.selectedItem, state.quantity, state.currentTab, canAct, state.isAdmin) 
                end
            end
        end
    end
end
end)

-- Если произошла ошибка или выход, возвращаем экран в нормальное состояние
gpu.setBackground(0x000000)
gpu.setForeground(0xFFFFFF)
gpu.fill(1, 1, W, H, " ")
if not success then
    print("Скрипт аварийно завершился: " .. tostring(err))
else
    print("Скрипт успешно завершен.")
end
