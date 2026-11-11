# Каталог ассетов

Все сторонние ассеты записываются сюда: что, откуда, лицензия, где лежит в проекте.

## Как передать паки
Скачать zip → на GitHub в репозитории `buro`: **Add file → Upload files** → положить в папку `assets_inbox/` (не распаковывая). Лимит веб-загрузки GitHub — 25 МБ на файл; все паки ниже меньше.

## Запрошено у владельца (всё CC0, указывать автора не обязательно)
| Пак | Зачем | Ссылка | Статус |
|---|---|---|---|
| Kenney — Furniture Kit | столы, стулья, кухня ресторана | https://kenney.nl/assets/furniture-kit | получен |
| Kenney — Food Kit | еда и посуда на столах (физ-предметы) | https://kenney-assets.itch.io/food-kit | получен |
| Kenney — Building Kit | стены, двери, окна служебных помещений | https://opengameart.org/content/building-kit | получен |
| Kenney — Factory Kit | техпомещение насосной; позже — утиная фабрика | https://kenney.nl/assets/factory-kit | получен |
| Quaternius — Animated Fish | рыбы, акула, скат за стеклом купола | https://quaternius.itch.io/lowpoly-animated-fish | получен |
| Kenney — Impact Sounds | удары, падения | kenney.nl → Assets → Audio (ссылка не проверена) | ждём |
| Kenney — Interface Sounds | звуки меню | kenney.nl → Assets → Audio (ссылка не проверена) | получен |

Проверено после загрузки: паки Kenney содержат GLB (импортируются в Godot напрямую); Factory Kit включает трубы, вентили, рычаги, шестерни, конвейеры; рыбы Quaternius — FBX/OBJ/Blend (7 моделей: 3 рыбы, акула, скат, дельфин, кит). В проект модели переносятся по мере надобности на этапе 5, архивы остаются в `assets_inbox/`.

## Делается студией
| Ассет | Примечание |
|---|---|
| Персонаж «Комбез» + лица | оригинальный, свой |
| Трубы, вентили, заглушки, изолента, инструменты | простая геометрия под физику, проще сделать точно под механику |
| Купол, вода | процедурно + шейдеры |
| Шрифт с кириллицей | из репозитория google/fonts (OFL), доступен напрямую |

## В проекте
| Ассет | Источник | Лицензия | Путь |
|---|---|---|---|
| Furniture Kit: tableRound, chairCushion, rugRound, pottedPlant и др. | Kenney | CC0 | `game/assets/furniture/` |
| Food Kit: plate, turkey, cake-birthday, fish, wine-red и др. + `Textures/colormap.png` | Kenney | CC0 | `game/assets/food/` |
| Fish1–3, Manta (из «Manta ray»), Shark (FBX, анимация Swim) | Quaternius | CC0 | `game/assets/fish/` |
| Factory Kit: machine (корпус насоса) + `Textures/colormap.png` | Kenney | CC0 | `game/assets/factory/` |
