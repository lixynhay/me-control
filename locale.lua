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

    -- ===== bugtorch =====
    ["Dirt"] = "Земля",
    ["Sand"] = "Песок",
    ["Stone Slab"] = "Каменная плита",
    ["Wood Slab"] = "Деревянная плита",

    -- ===== chisel =====
    ["End Stone"] = "Камень Края",
    ["Purpur Block"] = "Пурпуровый блок",
    ["Stained Glass"] = "Цветное стекло",
    ["Technical Block"] = "Технический блок",

    -- ===== metadrive =====
    ["Upgrade \"Discount\""] = "Улучшение «Скидка»",
    ["Upgrade \"Multiplier\""] = "Улучшение «Множитель»",

    -- ===== projectred =====
    ["Athame"] = "Атам",
    ["Auto Crafting Bench"] = "Верстак автокрафта",
    ["Battery"] = "Батарея",
    ["Battery Box"] = "Батарейный блок",
    ["Block of Copper"] = "Медный блок",
    ["Block of Electrotine"] = "Блок электротина",
    ["Block of Silver"] = "Серебряный блок",
    ["Block of Tin"] = "Оловянный блок",
    ["Charging Bench"] = "Зарядная станция",
    ["Electric Screwdriver"] = "Электрическая отвёртка",
    ["Electrotine Generator"] = "Генератор электротина",
    ["Filtered Importer"] = "Фильтруемый импортёр",
    ["Fire Starter"] = "Огниво",
    ["Frame Linear Actuator"] = "Линейный актуатор рамы",
    ["Frame Motor"] = "Мотор рамы",
    ["Glowing Silicon Compound"] = "Светящееся кремниевое соединение",
    ["IC Gate"] = "IC-вентиль",
    ["Inductive Furnace"] = "Индукционная печь",
    ["Infused Ender Pearl"] = "Наполненный эндер-жемчуг",
    ["Item Crafting Extension chip"] = "Чип расширения крафта предметов",
    ["Jetpack"] = "Реактивный ранец",
    ["Network Latency pipe"] = "Труба сетевой задержки",
    ["Network Valve pipe"] = "Труба сетевого клапана",
    ["Null-Logic Routing Chip"] = "Чип маршрутизации нулевой логики",
    ["Null-Logic Upgrade Chip"] = "Чип улучшения нулевой логики",
    ["Project Bench"] = "Верстак ProjectRed",
    ["Recipe Plan"] = "План рецепта",
    ["Red Iron Compound"] = "Соединение красного железа",
    ["Red Silicon Compound"] = "Соединение красного кремния",
    ["Sail"] = "Парус",
    ["Sandy Coal Compound"] = "Соединение песчаного угля",
    ["Solar Panel"] = "Солнечная панель",
    ["Teleposer"] = "Телепозер",
    ["Woven Cloth"] = "Тканое полотно",

    -- ===== etfuturum =====
    ["Black Bed"] = "Чёрная кровать",
    ["Blue Bed"] = "Синяя кровать",
    ["Brown Bed"] = "Коричневая кровать",
    ["Cyan Bed"] = "Бирюзовая кровать",
    ["Gray Bed"] = "Серая кровать",
    ["Green Bed"] = "Зелёная кровать",
    ["Light Blue Bed"] = "Голубая кровать",
    ["Light Gray Bed"] = "Светло-серая кровать",
    ["Lime Bed"] = "Лаймовая кровать",
    ["Magenta Bed"] = "Пурпурная кровать",
    ["Orange Bed"] = "Оранжевая кровать",
    ["Pink Bed"] = "Розовая кровать",
    ["Purple Bed"] = "Фиолетовая кровать",
    ["Red Bed"] = "Красная кровать",
    ["White Bed"] = "Белая кровать",
    ["Yellow Bed"] = "Жёлтая кровать",
    ["Cartography Table"] = "Стол картографа",
    ["Composter"] = "Компостер",
    ["Copper to Iron Shulker Box Upgrade"] = "Улучшение шалкер-бокса: медь → железо",
    ["Copper to Silver Shulker Box Upgrade"] = "Улучшение шалкер-бокса: медь → серебро",
    ["Diamond to Crystal Shulker Box Upgrade"] = "Улучшение шалкер-бокса: алмаз → кристалл",
    ["Diamond to Obsidian Shulker Box Upgrade"] = "Улучшение шалкер-бокса: алмаз → обсидиан",
    ["Fletching Table"] = "Стол лучника",
    ["Gold to Diamond Shulker Box Upgrade"] = "Улучшение шалкер-бокса: золото → алмаз",
    ["Grindstone"] = "Точильный камень",
    ["Iron to Gold Shulker Box Upgrade"] = "Улучшение шалкер-бокса: железо → золото",
    ["Lectern"] = "Кафедра",
    ["Loom"] = "Ткацкий станок",
    ["Silver to Gold Shulker Box Upgrade"] = "Улучшение шалкер-бокса: серебро → золото",
    ["Smithing Table"] = "Кузнечный стол",
    ["Stonecutter"] = "Камнерез",
    ["Vanilla to Copper Shulker Box Upgrade"] = "Улучшение шалкер-бокса: обычный → медь",
    ["Vanilla to Iron Shulker Box Upgrade"] = "Улучшение шалкер-бокса: обычный → железо",

    -- ===== enderio =====
    ["Alloy"] = "Сплав",
    ["Alloy Block"] = "Блок сплава",
    ["Big Item Filter"] = "Большой фильтр предметов",
    ["Buffer"] = "Буфер",
    ["Capacitor"] = "Конденсатор",
    ["Capacitor Bank"] = "Батарея конденсаторов",
    ["Conduit Facade"] = "Фасад трубы",
    ["Dark Steel Anvil"] = "Наковальня из тёмной стали",
    ["Energy Conduit"] = "Энергетическая труба",
    ["Fluid Conduit"] = "Жидкостная труба",
    ["Grinding Ball"] = "Мелющий шар",
    ["Item Conduit"] = "Труба для предметов",
    ["Item Filter"] = "Фильтр предметов",
    ["Light Node"] = "Световой узел",
    ["Limited Item Filter"] = "Ограниченный фильтр предметов",
    ["Machine Parts"] = "Детали машин",
    ["Materials"] = "Материалы",
    ["ME Conduit"] = "МЭ-труба",
    ["Network Conduit (OC)"] = "Сетевая труба (OC)",
    ["Painted Slab"] = "Крашеная плита",
    ["Powder"] = "Порошок",
    ["Powered Light"] = "Электрический светильник",
    ["Redstone Conduit"] = "Редстоуновая труба",
    ["Remote Awareness Upgrade"] = "Улучшение удалённого оповещения",
    ["Staff of Teleportation"] = "Посох телепортации",
    ["Zombie Electrode"] = "Зомби-электрод",

    -- ===== uiesingularities =====
    ["Aluminum Brass Singularity"] = "Алюминиево-латунная сингулярность",
    ["Aluminum Singularity"] = "Алюминиевая сингулярность",
    ["Alumite Singularity"] = "Алюмитовая сингулярность",
    ["Amordrine Singularity"] = "Амордриновая сингулярность",
    ["Angmallen Singularity"] = "Ангмалленовая сингулярность",
    ["Ardite Singularity"] = "Ардитовая сингулярность",
    ["Awakened Draconium Singularity"] = "Сингулярность пробуждённого драконьего металла",
    ["Bitumen Singularity"] = "Битумная сингулярность",
    ["Black Steel Singularity"] = "Сингулярность чёрной стали",
    ["Blue Gem Singularity"] = "Сингулярность синего самоцвета",
    ["Blutonium Singularity"] = "Блутониевая сингулярность",
    ["Brass Singularity"] = "Латунная сингулярность",
    ["Bronze Singularity"] = "Бронзовая сингулярность",
    ["Carbon Singularity"] = "Углеродная сингулярность",
    ["Celenegil Singularity"] = "Целенегиловая сингулярность",
    ["Charcoal Singularity"] = "Сингулярность древесного угля",
    ["Coal Singularity"] = "Угольная сингулярность",
    ["Cobalt Singularity"] = "Кобальтовая сингулярность",
    ["Compressed Iron Singularity"] = "Сингулярность сжатого железа",
    ["Conductive Iron Singularity"] = "Сингулярность проводящего железа",
    ["Crystal Singularity"] = "Кристальная сингулярность",
    ["Cyanite Singularity"] = "Цианитовая сингулярность",
    ["Damascus Steel Singularity"] = "Сингулярность дамасской стали",
    ["Dark Steel Singularity"] = "Сингулярность тёмной стали",
    ["Desichalkos Singularity"] = "Десихалкосовая сингулярность",
    ["Diamond Singularity"] = "Алмазная сингулярность",
    ["Draconium Singularity"] = "Драконья сингулярность",
    ["Electrical Steel Singularity"] = "Сингулярность электротехнической стали",
    ["Electrotine Singularity"] = "Электротиновая сингулярность",
    ["Electrum Singularity"] = "Электрумовая сингулярность",
    ["Emerald Singularity"] = "Изумрудная сингулярность",
    ["Ender Singularity"] = "Эндер-сингулярность",
    ["Energetic Alloy Singularity"] = "Сингулярность энергетического сплава",
    ["Fairy Singularity"] = "Фейри-сингулярность",
    ["Flux Crystal Singularity"] = "Сингулярность кристалла потока",
    ["Fluxed Electrum Singularity"] = "Сингулярность флюсового электрума",
    ["Glue Singularity"] = "Клеевая сингулярность",
    ["Graphite Singularity"] = "Графитовая сингулярность",
    ["Haderoth Singularity"] = "Хадеротовая сингулярность",
    ["Hepatizon Singularity"] = "Гепатизоновая сингулярность",
    ["Inolashite Singularity"] = "Инолашитовая сингулярность",
    ["Invar Singularity"] = "Инваровая сингулярность",
    ["Ludicrite Singularity"] = "Лудикритовая сингулярность",
    ["Magnesium Singularity"] = "Магниевая сингулярность",
    ["Manyullyn Singularity"] = "Мануллиновая сингулярность",
    ["Osmium Singularity"] = "Осмиевая сингулярность",
    ["Palladium Singularity"] = "Палладиевая сингулярность",
    ["Peridot Singularity"] = "Перидотовая сингулярность",
    ["Phosphorus Singularity"] = "Фосфорная сингулярность",
    ["Pokefennium Singularity"] = "Покефенниумовая сингулярность",
    ["Potash Singularity"] = "Поташная сингулярность",
    ["Pulsating Iron Singularity"] = "Сингулярность пульсирующего железа",
    ["Quicksilver Singularity"] = "Ртутная сингулярность",
    ["Red Gem Singularity"] = "Сингулярность красного самоцвета",
    ["Redstone Alloy Singularity"] = "Сингулярность редстоунового сплава",
    ["Refined Glowstone Singularity"] = "Сингулярность очищенного светокамня",
    ["Refined Obsidian Singularity"] = "Сингулярность очищенного обсидиана",
    ["Ruby Singularity"] = "Рубиновая сингулярность",
    ["Saltpeter Singularity"] = "Селитровая сингулярность",
    ["Sapphire Singularity"] = "Сапфировая сингулярность",
    ["Shadow Steel Singularity"] = "Сингулярность теневой стали",
    ["Soularium Singularity"] = "Соулариумовая сингулярность",
    ["Steel Singularity"] = "Стальная сингулярность",
    ["Sulfur Singularity"] = "Серная сингулярность",
    ["Tartarite Singularity"] = "Тартаритовая сингулярность",
    ["Titanium Singularity"] = "Титановая сингулярность",
    ["Tungsten Singularity"] = "Вольфрамовая сингулярность",
    ["Unstable Ingot Singularity"] = "Сингулярность нестабильного слитка",
    ["Uranium Singularity"] = "Урановая сингулярность",
    ["Vibrant Alloy Singularity"] = "Сингулярность яркого сплава",
    ["White Gem Singularity"] = "Сингулярность белого самоцвета",
    ["Yellorium Singularity"] = "Йеллориумовая сингулярность",
    ["Zinc Singularity"] = "Цинковая сингулярность",
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