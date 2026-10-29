# ГГ: отдельный Live2D-экземпляр для редактора персонажа

Дата: 2026-10-29. Исполнитель: macOS Live2D agent. Статус: native-модель, схема внешности и итоговый modal визуально проверены.

## Что создано

- `assets/characters/protagonist_gg/gg.json` задаёт отдельные `id: gg`, имя «ГГ» и происхождение `retained_mdrg_study`.
- `assets/characters/protagonist_gg/model.model3.json` ссылается на уже сохранённые MOC/три текстуры/physics `interaction_model`; бинарные данные не копировались. У экземпляра нет motion/expression, в отличие от исследовательской мастерской.
- `data/characters/protagonist_live2d.json` задаёт допустимые реальные параметры модели, три полных повседневных комплекта и ограниченные оттенки.
- `scripts/characters/protagonist_appearance.gd` содержит чистые `static normalize_appearance(value)` и `static validate_appearance(value)` без GUI и native-зависимости.
- `scripts/characters/protagonist_live2d.gd` — отдельный `Node2D` view. Его состояние не меняет NPC или общую модель.

## Контракт для UI и сохранения

`var view = preload("res://scripts/characters/protagonist_live2d.gd").new(); add_child(view); view.load_gg()` возвращает `bool`, а `fully_loaded` и `load_failed(message)` отражают результат загрузки. `view.get_controls()` возвращает JSON-профиль для построения элементов редактора. `apply_appearance(dict) -> bool`, `get_appearance() -> Dictionary`, `set_shape(id, value)`, `set_outfit(id)`, `set_palette(group_id, option_id)`, `reset_appearance()` и `randomize_appearance(seed)` работают только с допустимыми параметрами. `set_framing("face"|"body", size, zoom, pan, head_tilt)` меняет только вид зеркала; наклон головы не сериализуется.

Сериализуемое поле `profile.appearance.live2d`:

```json
{
  "schema": 1,
  "model_id": "gg",
  "shape": {
    "ParamAssSize": 0.0,
    "ParamThighSize": 0.0,
    "ParamCalfSize": 0.0,
    "ParamFootLength": 0.0,
    "ParamFootWidth": 0.0,
    "ParamBoobSize": 0.0
  },
  "outfit": "hoodie_pants",
  "palette": {
    "skin": "original",
    "hair": "original",
    "eyes": "original",
    "top": "original",
    "bottom": "original"
  }
}
```

Все шесть `shape` — native Cubism morph в диапазоне −1…1. Комплекты: `hoodie_pants` (default), `shirt_skirt`, `dress`. Оттенки задаются конечными swatch ID из `palette_groups`, применяются через `MeshInstance2D.self_modulate` к видимым drawable и не являются новым нарисованным атласом.

## Выполненная проверка

В собственной изолированной копии `.cache/tests/gg-live2d-20261029` с отдельным `user://` запущен Godot 4.7.2/macOS gd_cubism 0.9.1: `tests/characters/protagonist_live2d.gd` — **34 pass, 0 fail**. Проверены реальная загрузка MOC, отдельный ID, одетый default, шесть morph/гардероб, удержание значений и видимых tint после кадров, JSON round trip, восстановление в новом независимом native-инстансе, reset и seeded randomize. `tests/characters/protagonist_appearance.gd` выполнен отдельно без addon: **0 fail, native_available=false**; schema 1.5, неизвестные поля, swatch и значения вне диапазона отвергнуты.

На реальном OpenGL/Metal рендере без пользовательского ввода просмотрены `body-default.png`, `body-custom.png`, `face-custom.png`, `shape-small.png`, `shape-large.png` в `.artifacts/tests/gg-live2d-20261029/`. Исходный default одет; `skin=peach`, `hair=copper`, `eyes=sea`, розовый верх и синий низ видны на модели. При одинаковой одежде значения груди/бёдер −1 и +1 визуально меняют силуэт. Крупный кадр лица после исправления содержит уши и шляпу целиком.

Отдельный scripted capture **итогового** `character_creation_modal.gd` выполнен в минимальном UI fixture на 1440×900 и 700×900: `ui-desktop-body.png`, `ui-desktop-face.png`, `ui-desktop-face-colors.png`, `ui-narrow-face.png`, `ui-narrow-body.png`. Fixture содержит реальный modal, UI helpers, модель и фон, но локальные заглушки только для `Gameplay.creation_budget`/`GameSession` stat labels: это визуальная проверка modal, **не интегрированный gameplay**. Загрузка модели прошла без runtime ошибок. Все пять снимков просмотрены: обе компоновки показывают одетую модель, подписи и кнопки зеркала читаются, параметры/палитра выбираются, узкая панель имеет прокрутку. На 700×900 body framing уменьшен до 0.85, чтобы голова не пересекала поясняющую строку. Автор UI исправил порядок слоёв (`zoom_row.z_index=1000` и остальные оверлеи); финальные PNG пересняты с этим production-кодом, без локальной UI-подмены. Оттенки в селекторах соответствуют окрашенной модели.

## Точные ограничения

Retained `interaction_model` — исследовательский Cubism asset, визуально женский, с кошачьими ушами и аксессуарами. Это не утверждённый оригинальный EroInc арт по `docs/art/characters-v2/STYLE.md`. В репозитории есть `.moc3` и текстуры, но нет исходного `.cmo3`/Cubism authoring rig для отдельного пола, формы лица, причёски или независимого нового GG. `ParamHead*`, брови и радужка относятся к позе/мимике, поэтому не записаны как анатомия. Цвета — умножение на существующий атлас, без замены рисунка. Для полноценного Fallout-подобного визуального набора нужен отдельный утверждённый исходный rig/арт и его экспорт; эта работа создаёт честный технический редактор на доступных параметрах.
