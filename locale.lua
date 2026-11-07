-- locale.lua — русские названия предметов.
-- Основной словарь — locale_generated.lua (byLabel: английское имя -> русское),
-- сгенерирован из языковых файлов модпака.
-- Ручные переопределения:
--   locale.manual         — по registry id (name), приоритетнее сгенерированных
--   locale.manualByLabel  — по английскому отображаемому имени (для модов без ru)

local locale = {}
locale.names = {}
locale.byLabel = {}

-- Надёжная загрузка сгенерированного словаря:
-- сначала require, затем прямой loadfile (на случай, если package.path не видит /home)
local function loadGenerated()
    local ok, gen = pcall(require, "locale_generated")
    if ok and type(gen) == "table" then return gen end
    for _, path in ipairs({ "/home/locale_generated.lua", "locale_generated.lua" }) do
        local chunk = loadfile(path)
        if chunk then
            local ok2, res = pcall(chunk)
            if ok2 and type(res) == "table" then return res end
        end
    end
    return nil
end

local gen = loadGenerated()
if type(gen) == "table" then
    if type(gen.names) == "table" then
        for k, v in pairs(gen.names) do locale.names[k] = v end
    end
    if type(gen.byLabel) == "table" then
        for k, v in pairs(gen.byLabel) do locale.byLabel[k] = v end
    end
end

-- Ручные переопределения по registry id (приоритетнее сгенерированных)
locale.manual = {
    -- ["appliedenergistics2:certus_quartz_crystal"] = "Кристалл истинного кварца",
}
for k, v in pairs(locale.manual) do locale.names[k] = v end

-- Ручные переводы по английскому имени (моды без собственной ru-локализации)
locale.manualByLabel = {
    -- ===== openperipheraladdons =====
    ["Advanced Combat Processor"] = "Продвинутый боевой процессор",
    ["Capacitor"] = "Конденсатор",
    ["Carbon"] = "Углерод",
    ["Coiled Wire"] = "Витой провод",
    ["Combat Processor"] = "Боевой процессор",
    ["Data-Link"] = "Канал передачи данных",
    ["Duck Antenna"] = "Утиная антенна",
    ["Electrode"] = "Электрод",
    ["Focus Lense"] = "Фокусирующая линза",
    ["Heat Sinks"] = "Радиаторы",
    ["Heavy Energy Cell"] = "Тяжёлая энергоячейка",
    ["Infrasound Emitter"] = "Излучатель инфразвука",
    ["Item Selector"] = "Селектор предметов",
    ["Laser Sight"] = "Лазерный прицел",
    ["LCD Screen"] = "ЖК-экран",
    ["LED"] = "Светодиод",
    ["Light Energy Cell"] = "Лёгкая энергоячейка",
    ["Matrix Component"] = "Матричный компонент",
    ["Mechano-Stabilizer"] = "Механостабилизатор",
    ["Medium Energy Cell"] = "Средняя энергоячейка",
    ["Microcontroller"] = "Микроконтроллер",
    ["Nano GPS"] = "Нано-GPS",
    ["OpenMech: Warrior"] = "OpenMech: Воин",
    ["Optical Lense"] = "Оптическая линза",
    ["Opto-Isolator"] = "Оптоизолятор",
    ["Peripheral Proxy"] = "Прокси периферии",
    ["PIM"] = "PIM",
    ["Plastic Casing"] = "Пластиковый корпус",
    ["Prepared Circuit Board"] = "Подготовленная плата",
    ["Printed Circuit Board"] = "Печатная плата",
    ["Rationalizer"] = "Рационализатор",
    ["Remote"] = "Пульт",
    ["Resistor"] = "Резистор",
    ["Ribbon Cable"] = "Ленточный кабель",
    ["Robot Controller"] = "Контроллер робота",
    ["Scanning Sensor"] = "Сканирующий сенсор",
    ["Sensor"] = "Сенсор",
    ["Silislime Rubber"] = "Силислимовая резина",
    ["Solar Cell"] = "Солнечная батарея",
    ["Target Assessment Unit"] = "Модуль оценки цели",
    ["Terminal Glasses"] = "Терминальные очки",
    ["Terminal Glasses Bridge"] = "Мост терминальных очков",
    ["Thin Wire"] = "Тонкий провод",
    ["Ticket Machine"] = "Билетный автомат",
    ["Tier 1 Inventory Unit"] = "Модуль инвентаря ур. 1",
    ["Tier 1 Laser Unit"] = "Лазерный модуль ур. 1",
    ["Tier 1 Movement Unit"] = "Модуль движения ур. 1",
    ["Tier 1 Sensor Unit"] = "Сенсорный модуль ур. 1",
    ["Tier 1 Targeting Unit"] = "Модуль наведения ур. 1",
    ["Tier 2 Inventory Unit"] = "Модуль инвентаря ур. 2",
    ["Tier 2 Laser Unit"] = "Лазерный модуль ур. 2",
    ["Tier 2 Movement Unit"] = "Модуль движения ур. 2",
    ["Tier 2 Sensor Unit"] = "Сенсорный модуль ур. 2",
    ["Tier 2 Targeting Unit"] = "Модуль наведения ур. 2",
    ["Tier 3 Inventory Unit"] = "Модуль инвентаря ур. 3",
    ["Tier 3 Laser Unit"] = "Лазерный модуль ур. 3",
    ["Tier 3 Movement Unit"] = "Модуль движения ур. 3",
    ["Tier 3 Sensor Unit"] = "Сенсорный модуль ур. 3",
    ["Tier 3 Targeting Unit"] = "Модуль наведения ур. 3",
    ["Transistor"] = "Транзистор",
    ["Wireless Keyboard"] = "Беспроводная клавиатура",

    -- ===== opensecurity =====
    ["Alarm"] = "Сигнализация",
    ["Biometric Reader"] = "Биометрический считыватель",
    ["Card Writer"] = "Устройство записи карт",
    ["Cooldown Upgrade"] = "Улучшение перезарядки",
    ["Damage Upgrade"] = "Улучшение урона",
    ["Data Block"] = "Блок данных",
    ["Display Panel"] = "Панель дисплея",
    ["Door Controller"] = "Контроллер двери",
    ["Energy Turret"] = "Энергетическая турель",
    ["Energy Upgrade"] = "Энергетическое улучшение",
    ["Entity Detector"] = "Детектор сущностей",
    ["Keypad"] = "Кодовая панель",
    ["KVM Switch"] = "KVM-переключатель",
    ["Magnetic Card Reader"] = "Считыватель магнитных карт",
    ["Magnetic Strip Card"] = "Карта с магнитной полосой",
    ["Movement Upgrade"] = "Улучшение движения",
    ["Private Security Door"] = "Частная защищённая дверь",
    ["RFID Card"] = "RFID-карта",
    ["RFID Reader"] = "RFID-считыватель",
    ["RFID Reader Card"] = "Карта RFID-считывателя",
    ["Secure Network Card"] = "Защищённая сетевая карта",
    ["Security Door"] = "Защищённая дверь",
    ["Switchable Hub"] = "Коммутируемый хаб",

    -- ===== computronics =====
    ["Light Board"] = "Световая плата",
    ["Magical Memory (Creative)"] = "Магическая память (креатив)",
    ["Portable Tape Drive"] = "Портативный ленточный накопитель",
    ["Rack Capacitor"] = "Конденсатор стойки",
    ["Server Self-Destructor"] = "Самоуничтожитель сервера",
    ["Sound Card"] = "Звуковая карта",
    ["Speech Box"] = "Речевой модуль",
    ["Speech Upgrade"] = "Речевое улучшение",
    ["Switch Board"] = "Коммутационная панель",
}
for k, v in pairs(locale.manualByLabel) do locale.byLabel[k] = v end

-- itemName — registry id (name), damage — метаданные, fallback — игровое (английское) имя.
function locale.getName(itemName, damage, fallback)
    if itemName then
        local v = locale.names[itemName]
        if v ~= nil then
            if type(v) == "table" then
                local d = tonumber(damage) or 0
                return v[d] or v["*"] or fallback
            end
            return v
        end
    end
    if fallback then
        local clean = tostring(fallback):gsub("§.", "")
        clean = clean:match("^%s*(.-)%s*$") or clean
        if clean ~= "" and locale.byLabel[clean] then
            return locale.byLabel[clean]
        end
    end
    return fallback
end

return locale