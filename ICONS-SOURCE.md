# Иконки RoteCode VK для базы 1.11

Источник: предоставленная пользователем папка `../RoteCode VK/OpenVK Me`, репозиторий https://github.com/bod904/OpenVK-iOS . README исходного проекта указывает автором Veselcraft.

Импортированы только изображения:

| Источник | Ресурс клиента |
| --- | --- |
| news.png / news@2x.png | News.png / News@2x.png |
| friends.png / friends@2x.png | Friends.png / Friends@2x.png |
| messages.png / messages@2x.png | Messages.png / Messages@2x.png |
| settings.png / settings@2x.png | Settings.png / Settings@2x.png |
| icon.png / icon@2x.png | Icon.png / Icon@2x.png, без изменения файлов |
| icon@2x.png | Icon-60@2x, Icon-72 (1x/2x), Icon-76 (1x/2x), приведены к размерам из существующих Info.plist и проекта |
| siluette.png | Avatar.png, уменьшена до существующих 100×100 |

Чёрный цвет значков меню заменён светло-серым для тёмного меню; исходная альфа-маска и размеры сохранены. Другие иконки не заменены: в источнике нет соответствующих значков. first/second — геометрические заглушки, они не использованы. Код, плеер, сетевые запросы, фоновые изображения и кнопки из исходного проекта не импортировались. Info.plist и версия 1.11 сохранены.

Повторить импорт: `python3 tools/import_rote_icons.py`, либо передать путь к папке с PNG первым аргументом. Скрипт требует Pillow и не нужен для сборки в Xcode. `tools/reference_style.py` генерирует прежние значки, поэтому после его запуска нужно повторить импорт.
