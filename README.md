# ME-Control (OC-Terminal)

Панель управления МЭ-сетью (Applied Energistics 2) для OpenComputers.

## 🚀 Возможности
* Просмотр МЭ-сети и инвентаря игрока (через PIM).
* Выдача и сдача предметов (включая NBT-предметы).
* Поиск по названию (с поддержкой кириллицы).
* Система прав: User / Admin / TechAdmin.
* Баны с указанием причины и срока.
* Логи операций (кто, когда и что сдал/забрал).
* Мониторинг запасов с оповещениями (редстоун + звук).
* Статистика МЭ-сети: предметы, типы, энергия, занятость дисков (байты и типы).
* Красивый GUI с прогресс-барами и «зеброй».

## 🛠️ Установка
1. Установите интернет-карту в компьютер (для загрузки файлов).
2. Загрузите файлы проекта в `/home`:
   ```bash
   wget https://raw.githubusercontent.com/lixynhay/me-control/main/main.lua
   wget https://raw.githubusercontent.com/lixynhay/me-control/main/ui.lua
   wget https://raw.githubusercontent.com/lixynhay/me-control/main/me_api.lua
   wget https://raw.githubusercontent.com/lixynhay/me-control/main/db.lua
   wget https://raw.githubusercontent.com/lixynhay/me-control/main/config.lua
   ```
3. Запустите:
   ```bash
   main.lua
   ```

## 💾 Ёмкость хранилища

На вкладке «Статистика» показывается занятость дисков. В большинстве сборок OC 1.7.10
у `me_interface` нет метода `getCells()`, поэтому общий объём сети неизвестен —
панель показывает только занятый объём с пометкой «оценка занятого».

Чтобы видеть точный прогресс-бар с процентами, укажите ёмкость вручную в `config.lua`:

```lua
config.storage = {
    -- Общая ёмкость МЭ-сети в байтах (например, 4 ячейки по 4k = 16384).
    totalBytes = 16384
}
```

Оставьте `nil` — будет использоваться автоматическая оценка.

## 📜 Лицензия
MIT