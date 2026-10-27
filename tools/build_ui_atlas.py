"""Build the local UI review atlas from actual Godot capture reports."""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "ui"
CAPTURES = OUT / "captures"
DATASETS = {
    "1920 × 1080": "windows-v2-1920",
    "1366 × 768": "windows-v2-1366",
    "2560 × 1080": "windows-v2-ultrawide",
}
TITLES = {
    "place": "Игровой HUD", "map": "Карта города", "profile": "Персонаж",
    "inventory": "Сумка", "people": "Люди и отношения", "phone": "Телефон",
    "journal": "Журнал", "activities": "Занятия", "work": "Работа и деньги",
    "club": "Мой клуб", "home": "Мой дом", "health": "Самочувствие",
    "family": "Семья", "digital": "Цифровой мир", "collection": "Воспоминания",
    "interface": "Интерфейс и управление", "sections": "Все разделы",
    "queue": "План действий", "inventory-text-125": "Сумка · текст 125 %",
    "interface-text-125": "Управление · текст 125 %", "new-game": "Новая игра",
    "difficulty": "Сложность", "mirror": "Зеркало и создание героя",
    "main-menu": "Главное меню", "settings": "Настройки", "load-game": "Загрузка",
    "pause-menu": "Пауза", "save-game": "Сохранение", "combat": "Конфликт",
    "minigame": "Испытание", "conversation": "Разговор",
    "profile-skills": "Персонаж · навыки", "profile-perks": "Персонаж · особенности",
    "phone-wallpapers":"Телефон · выбор обоев", "phone-rain":"Телефон · другой фон",
    "phone-contacts":"Телефон · контакты", "phone-messages":"Телефон · сообщения",
    "phone-calendar":"Телефон · встречи", "phone-bank":"Телефон · банк",
    "phone-chat":"Телефон · переписка", "phone-text-125":"Телефон · текст 125 %",
    "activities-training":"Занятия · тренировки", "activities-university":"Занятия · учёба",
    "work-jobs":"Работа · вакансии", "work-channel":"Работа · канал",
    "health-treatment":"Самочувствие · лечение", "health-reproduction":"Самочувствие · репродуктивное здоровье",
    "home-properties":"Дом · недвижимость",
    "home-household":"Дом · домочадцы", "activities-games":"Занятия · испытания",
    "journal-stories":"Дневник · личные истории", "journal-history":"Дневник · хроника",
    "journal-achievements":"Дневник · достижения", "work-shop":"Магазин", "work-assets":"Имущество",
    "health-adult_health":"Самочувствие · особенности", "health-repro-protection":"Личное здоровье · защита",
    "health-repro-family":"Личное здоровье · планы", "family-duties":"Семья · обязанности",
    "family-budget":"Семья · общие деньги", "family-history":"Семья · история", "digital-history":"Цифровой мир · история",
    "person-about":"Человек · знакомство", "person-together":"Человек · время вместе",
    "person-gifts":"Человек · подарки", "person-history":"Человек · история отношений", "risk":"Конфликт и риск",
    "gathering":"Встреча компанией", "growth-skills":"Практика навыков", "growth-needs":"Настройки потребностей",
    "growth-habits":"Полезные привычки", "growth-text-125":"Практика · текст 125 %",
    "livelihood-jobs":"Подработки", "livelihood-orders":"Заказы", "livelihood-goals":"Личные цели",
    "livelihood-home":"Уют дома", "personal-story":"Личная история", "curriculum":"Моё расписание",
    "confirmation":"Подтверждение решения", "mirror-character":"Зеркало · характер",
    "settings-text":"Настройки · текст", "settings-language":"Настройки · язык", "about":"Об игре",
    "character-workshop":"Мастерская персонажей", "minigame-blackjack":"Двадцать одно",
    "minigame-reaction":"Реакция", "minigame-guess":"Угадать число", "minigame-lockpick":"Учебный замок",
    "minigame-strength":"Проверка силы", "minigame-pushups":"Отжимания",
    "intimacy-invitation":"Личная встреча · предложение", "intimacy-decision":"Личная встреча · решение",
    "guided-room":"Первый день · комната", "guided-journal":"Первый день · журнал",
}
NOTES = {
    "place": "Место, время, одна цель, основные ресурсы и небольшие иконки. Пустой план скрыт; Q открывает планирование.",
    "inventory": "Сетка предметов с растровыми иллюстрациями, выбранный предмет справа и одно основное действие. Поиск, категории и сортировка сохраняются при переходах. Просмотр не расходует время.",
    "phone":"Физический телефон поверх игровой сцены: цветные круглые растровые значки приложений в духе Android, подписи, часы и сменные обои. Кнопка «Обои» открывает персонализацию; Esc возвращает назад, затем убирает телефон.",
    "phone-wallpapers":"Три оригинальных фона ImageGen и однотонный вариант. Миниатюра выбирает фон, «Установить» применяет его. Можно импортировать PNG, JPG или WebP и настроить затемнение. Настройки хранятся отдельно от игровых слотов.",
    "phone-chat":"Настоящая переписка внутри телефона: свой текст, черновики, ответы NPC и темы разговора. Новые сообщения сохраняют место при чтении старой истории.",
    "journal":"Дневник с растровой кожаной обложкой и бумагой. Записи слева, выбранное дело и следующий шаг справа. Заголовки, прогресс и кнопки остаются настоящими контролами Godot.",
    "home":"План комнаты и предметы мебели. Выбор, поворот и размещение вызывают реальные команды; недвижимость и домочадцы открываются вкладками.",
    "combat":"Участники конфликта, здоровье, выносливость, прогноз действий и тактика. Обычная навигация и ожидание скрыты на время столкновения.",
    "profile": "Персонаж слева, один выбранный раздел справа: характеристики, навыки или особенности. Числа берутся из симуляции.",
    "people": "Поиск по имени, фильтры контактов и людей рядом. Профиль открывает настоящие отношения и личные дела.",
    "queue": "До шести действий. Shift + действие добавляет его в план. Выполнение начинается только по ▶. Недоступность, сроки и переход в другое окно останавливают план.",
    "sections": "Полная навигация появляется только по F1. На постоянной игровой сцене большого списка разделов нет.",
    "new-game": "Настройки мира и жителей выбираются до пролога. Существующие сохранения не изменяются.",
    "mirror": "Создание героя остаётся отражением в домашнем зеркале на сюжетном сигнале open_character_creator.",
    "health": "Портрет и реальные потребности показаны первыми. Лечение и репродуктивное здоровье открываются отдельными вкладками.",
    "growth-skills":"Все направления доступны в списке с фильтром. Справа — выбранное занятие, действительный прогресс, затраты и действие. Открытие окна не расходует время.",
    "livelihood-jobs":"Работа выбирается слева; условия и оплата читаются справа. Фильтр по навыку. Обычная смена и испытание используют настоящие команды игры.",
    "curriculum":"Выбор 2–4 дисциплин и спортивной секции. Заполненные предметы выделены, при достижении лимита остальные временно отключаются. Esc открывает меню без потери выбора.",
    "settings":"Настоящие вкладки Игра / Текст / Язык. На экране открыта одна группа настроек.",
    "save-game":"Три колонки, ограниченная область прокрутки, отдельные кнопки сохранения и удаления, клавиатурная активация. Заполненные карточки в этом обзоре — тестовые данные; файлы сохранений не создавались.",
    "load-game":"Авто, быстрые и ручные сохранения доступны из двух вкладок. Превью в обзоре демонстрационные, из тестового мира.",
    "confirmation":"Подтверждения используют игровой стиль. По умолчанию выбрана отмена. Закрытие окна не выполняет действие.",
}


def read_reports():
    datasets = {}
    for label, directory in DATASETS.items():
        path = CAPTURES / directory / "report.json"
        if not path.exists():
            continue
        report = json.loads(path.read_text(encoding="utf-8-sig"))
        datasets[label] = {
            entry["id"]: {
                "path": f"captures/{directory}/{entry['id']}.png",
                "bounds_ok": entry["main_window_inside_viewport"],
                "saved": entry["saved"],
            }
            for entry in report["captures"]
        }
    return datasets


def result_from_log(path, marker):
    if not path.exists():
        return {}
    matches = re.findall(re.escape(marker) + r"\s+(\{[^\n]+\})", path.read_text(encoding="utf-8-sig"))
    return json.loads(matches[-1]) if matches else {}


def main():
    datasets = read_reports()
    screens = [
        {"id": key, "title": TITLES.get(key, key), "note": NOTES.get(key, "Существующий игровой раздел в общей лаконичной теме EroInc.")}
        for key in datasets["1920 × 1080"]
    ]
    research = ROOT.parent / ".research" / "school-0.981"
    verification = {
        "gameplay": result_from_log(research / "phase5" / "tests.log", "GAMEPLAY_RESULT"),
        "game_ui": result_from_log(OUT / "test-ui.log", "GAME_UI_RESULT"),
        "mechanics_pack": result_from_log(research / "tests-pack.log", "MECHANICS_RESULT"),
        "captures": sum(len(items) for items in datasets.values()),
        "all_capture_bounds_pass": all(item["bounds_ok"] and item["saved"] for data in datasets.values() for item in data.values()),
        "controller_validation": "Synthetic cancel input and keyboard focus; no physical controller session.",
        "review_source": "All images are native Godot captures from disposable worlds; save cards use in-memory fixtures. No existing save file was modified.",
        "known_shutdown_output": "The existing runtime reports 63 ObjectDB instances and 27 resources at exit; the same output was observed before UI changes.",
    }
    specification = {
        "date": "2026-10-27", "engine": "Godot 4.7.2 stable",
        "direction": "Собственный лаконичный игровой стиль EroInc: физический телефон, личный дневник, сумка и план комнаты; растровое искусство в ночной палитре и удобные повседневные действия.",
        "rules": [
            "Одна задача на экране. Остальные разделы открываются по F1 или горячим клавишам.",
            "Прозрачные сине-чёрные поверхности, тонкие горизонтальные линии, светлый текст. Выделение — бледно-голубое; оранжевый — для последствий и предупреждений.",
            "Внутренние группы отделяются отступами, а не вложенными рамками.",
            "Прогресс, предметы и последствия читаются из настоящего игрового состояния.",
            "План действий локален текущему сеансу; перед каждым шагом проводится повторная проверка. План не сохраняется в игровые слоты.",
            "Текст масштабируется от 90 до 125 процентов. Настройка хранится отдельно в user://interface.cfg.",
            "Телефон использует растровый корпус и сменные обои; настройки и копия своего изображения хранятся в user://phone, отдельно от игровых сохранений.",
            "Предметы, корпус телефона, дневник и обои — оригинальные изображения ImageGen. Текст, кнопки, состояния и простые навигационные пиктограммы остаются кодовыми элементами.",
            "Все подробные игровые окна используют общую растровую поверхность. Назад возвращает в предыдущий раздел; верхнее окно перехватывает игровые горячие клавиши и восстанавливает фокус при закрытии.",
            "Практика, подработки, расписание, личные истории, подтверждения и мини-игры входят в тот же интерфейс. Устаревшие дубли семейного окна и карточек сохранения удалены.",
        ],
        "palette": {"text": "#e4edf4", "secondary": "#9ab1c2", "selection": "#90c6e8", "consequences": "#da9a63"},
        "keys": {"I": "Сумка", "C": "Персонаж", "J": "Журнал", "M": "Карта", "R": "Люди", "P": "Телефон", "Q": "План", "F1": "Разделы", "H": "Скрыть HUD", "Esc / gamepad B": "Назад"},
        "sources": [
            {"title": "The Sims 4 · горячие клавиши и управление временем", "url": "https://www.ea.com/games/the-sims/tips-and-tricks?isLocalized=true"},
            {"title": "Black Desert · упрощение интерфейса", "url": "https://www.sa.playblackdesert.com/PT-BR/Wiki?wikiNo=14"},
        ],
        "screens": screens,
        "verification": verification,
    }
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "specification.json").write_text(json.dumps(specification, ensure_ascii=False, indent=2), encoding="utf-8")
    (OUT / "verification.json").write_text(json.dumps(verification, ensure_ascii=False, indent=2), encoding="utf-8")
    data = json.dumps({"datasets": datasets, "screens": screens}, ensure_ascii=False)
    html = r'''<!doctype html>
<html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>EroInc — Атлас интерфейса</title>
<style>
:root{color-scheme:dark;font:15px/1.5 system-ui,sans-serif;color:#e4edf4;background:#070e15}*{box-sizing:border-box}body{margin:0}button,select,a{font:inherit}button,select{background:transparent;color:inherit;border:0;border-bottom:1px solid #344c5d;padding:10px 14px;cursor:pointer}button:hover,button:focus-visible,a:focus-visible{color:#90c6e8;outline:1px solid #90c6e8}a{color:#90c6e8}header{display:flex;gap:22px;align-items:baseline;padding:24px 32px;border-bottom:1px solid #344c5d}header strong{font-size:24px;font-weight:500}header span{color:#9ab1c2}.layout{display:grid;grid-template-columns:248px 1fr;min-height:calc(100vh - 85px)}nav{border-right:1px solid #223746;padding:20px 16px;max-height:calc(100vh - 85px);overflow:auto}nav input{width:100%;padding:10px;margin-bottom:12px;color:#e4edf4;background:#102332;border:1px solid #344c5d;font:inherit}nav button{display:block;text-align:left;width:100%;border:0;font-size:14px;padding:9px 12px}nav button[aria-current=true]{color:#90c6e8;background:#152b3b;border-left:2px solid #90c6e8}main{padding:20px 30px;min-width:0}.toolbar{display:flex;gap:12px;align-items:center;flex-wrap:wrap}.toolbar h1{margin:0 auto 0 0;font-size:25px;font-weight:400}.frame{margin-top:22px;max-height:72vh;overflow:auto;background:#03070b;border-top:1px solid #344c5d;border-bottom:1px solid #344c5d}.frame img{display:block;width:100%;height:auto}.frame.actual img{width:auto;max-width:none}p{max-width:900px;color:#9ab1c2}small{color:#9ab1c2}footer{margin-top:24px;color:#9ab1c2;font-size:13px}details{margin-top:22px}summary{cursor:pointer;color:#90c6e8}li{margin:8px 0}.tag{font-size:12px;letter-spacing:.06em;text-transform:uppercase;color:#90c6e8}@media(max-width:850px){header{display:block;padding:16px}.layout{grid-template-columns:1fr}nav{display:flex;max-height:none;overflow:auto;gap:8px;border-right:0}nav button{width:auto;white-space:nowrap}main{padding:16px}.frame{max-height:none}}
</style>
<header><strong>ERO INC</strong><span>Атлас интерфейса · 27 октября 2026</span></header>
<div class="layout"><nav aria-label="Экраны игры" id="navigation"></nav><main>
<div class="toolbar"><h1 id="title"></h1><select id="resolution" aria-label="Разрешение"></select><button id="previous" aria-label="Предыдущий экран">←</button><button id="next" aria-label="Следующий экран">→</button><button id="actual">1:1</button></div>
<div class="frame" id="frame"><img id="screen" alt=""></div>
<p id="note"></p><small id="size"></small>
<details><summary>Правила интерфейса</summary><ul>
<li>Одна задача на экране; полная навигация открывается по F1.</li>
<li>Светлая типографика, прозрачные тёмные поверхности, минимум рамок. Художественная основа EroInc сохранена.</li>
<li>Q открывает план действий. Shift + действие добавляет его в очередь. Пустой план скрыт.</li>
<li>Телефон — отдельное устройство с приложениями и сменными обоями. Сумка использует сетку предметов; дневник — разворот с одной выбранной записью.</li>
<li>Растровые изображения ImageGen встроены в игровые окна. Надписи, кнопки, фокус и действия работают средствами Godot.</li>
<li>Просмотр окон не расходует время. Игровые действия вызывают существующую симуляцию.</li>
</ul><p><a href="specification.json">Спецификация</a> · <a href="verification.json">Результаты проверок</a></p></details>
<footer>Настоящие снимки Godot из отдельного тестового мира. Это не художественные макеты и не сохранённое прохождение игрока. Полный обзор содержит игровые окна, дополнительные вкладки, заполненные тестовые слоты и увеличенный текст.</footer>
</main></div>
<script>
const data=__DATA__;
let index=Math.max(0,data.screens.findIndex(s=>s.id==='growth-skills'));const nav=document.querySelector('#navigation'),resolution=document.querySelector('#resolution');
const search=document.createElement("input");search.placeholder="Найти окно…";search.setAttribute("aria-label","Поиск окон");nav.append(search);search.oninput=()=>{[...nav.querySelectorAll("button")].forEach((b,n)=>b.hidden=!data.screens[n].title.toLocaleLowerCase().includes(search.value.toLocaleLowerCase()))};
for(const name of Object.keys(data.datasets)){const o=document.createElement('option');o.textContent=name;resolution.append(o)}
for(let n=0;n<data.screens.length;n++){const b=document.createElement('button');b.textContent=data.screens[n].title;b.onclick=()=>{index=n;show()};nav.append(b)}
function show(){const s=data.screens[index],chosen=data.datasets[resolution.value][s.id],capture=chosen||data.datasets['1920 × 1080'][s.id];document.querySelector('#title').textContent=s.title;document.querySelector('#note').textContent=s.note;const img=document.querySelector('#screen');img.src=capture.path;img.alt=s.title+' — реальный экран Godot';document.querySelector('#size').textContent=(chosen?resolution.value:'1920 × 1080 · этот экран доступен в полном обзоре')+' · ← / → переключают экраны';[...nav.querySelectorAll("button")].forEach((b,n)=>b.setAttribute('aria-current',n===index));document.querySelector('#frame').classList.remove('actual')}
document.querySelector('#previous').onclick=()=>{index=(index+data.screens.length-1)%data.screens.length;show()};document.querySelector('#next').onclick=()=>{index=(index+1)%data.screens.length;show()};document.querySelector('#actual').onclick=()=>document.querySelector('#frame').classList.toggle('actual');resolution.onchange=show;
window.addEventListener('keydown',e=>{if(['INPUT','SELECT'].includes(document.activeElement.tagName))return;if(e.key==='ArrowRight'){e.preventDefault();document.querySelector('#next').click()}if(e.key==='ArrowLeft'){e.preventDefault();document.querySelector('#previous').click()}});show();
</script></html>'''
    (OUT / "index.html").write_text(html.replace("__DATA__", data), encoding="utf-8")
    print(json.dumps(verification, ensure_ascii=False))


if __name__ == "__main__":
    main()
