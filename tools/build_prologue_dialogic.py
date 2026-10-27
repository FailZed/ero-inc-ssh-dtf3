import argparse
import re
from pathlib import Path

from docx import Document


PROJECT_DIR = Path(__file__).resolve().parents[1]
SOURCE_DOCX = PROJECT_DIR / "docs" / "Пролог.docx"
TIMELINE_DIR = PROJECT_DIR / "TimeLine" / "prolog"
ROOT_TIMELINE = PROJECT_DIR / "TimeLine" / "prolog.dtl"


SCENES = [
    {
        "file": "prolog.dtl",
        "label": "prolog",
        "title": "Пролог",
        "start": "Пролог",
        "end": "god?: “Я помогу тебе все вспомнить, ты же не думаешь, что сможешь просто так покинуть это место?”",
        "next": "scene_02_warehouse_confrontation",
    },
    {
        "file": "scene_02_warehouse_confrontation.dtl",
        "label": "scene_02_warehouse_confrontation",
        "title": "Склад и толпа",
        "start": "ГГ собирается с силами",
        "end": "god?: “Правда и в этот раз ты так и не понял…”",
        "next": "scene_03_death_reset",
    },
    {
        "file": "scene_03_death_reset.dtl",
        "label": "scene_03_death_reset",
        "title": "Смерть и перезапуск",
        "start": "Ощущение времени замедляется",
        "end": "god?: “Посмотрим, что в этот раз ты выберешь. Надеюсь, ты сможешь стать лучше”",
        "next": "scene_04_night_wakeup",
    },
    {
        "file": "scene_04_night_wakeup.dtl",
        "label": "scene_04_night_wakeup",
        "title": "Ночное пробуждение",
        "start": "Резкое падение… шум в голове заставляют ГГ проснуться",
        "end": "ГГ пошел в ванную комнату",
        "next": "scene_05_mirror_and_photo",
    },
    {
        "file": "scene_05_mirror_and_photo.dtl",
        "label": "scene_05_mirror_and_photo",
        "title": "Зеркало и фотография",
        "start": "Пройдя по темному коридору ГГ стоит и черного проема в котором стоят тени толпы смотрящие на него",
        "end": "god?: “Может это напомнит тебе о твоем прошлом”",
        "next": "scene_06_flashback_park",
    },
    {
        "file": "scene_06_flashback_park.dtl",
        "label": "scene_06_flashback_park",
        "title": "Флешбэк и парк",
        "start": "Флешбэк",
        "end": "Обходя статую ГГ идет в глубь парка по аллее до моря",
        "next": "scene_07_thomas",
    },
    {
        "file": "scene_07_thomas.dtl",
        "label": "scene_07_thomas",
        "title": "Томас",
        "start": "Друг Томас: “Эй! Имя ГГ! Иди сюда”",
        "end": "“Да иди ты!” - выкрикнул ГГ",
        "next": "scene_08_embankment",
    },
    {
        "file": "scene_08_embankment.dtl",
        "label": "scene_08_embankment",
        "title": "Набережная",
        "start": "Проходя дальше по аллее уже начинал ощущаться теплый морской бриз",
        "end": "“(Что же там происходит то)” - мысли ГГ",
        "next": "scene_09_lyra_choice_point",
    },
    {
        "file": "scene_09_lyra_choice_point.dtl",
        "label": "scene_09_lyra_choice_point",
        "title": "Точка выбора",
        "start": "Пройдя еще ближе стало видно, что пару мальчишек и 3 девочки издеваются над одной девочкой в белом сарафане",
        "end": "Выбор заступиться или убежать",
        "next": "scene_10_intervene_and_escape",
    },
    {
        "file": "scene_10_intervene_and_escape.dtl",
        "label": "scene_10_intervene_and_escape",
        "title": "Заступничество и побег",
        "start": "Выбор заступиться",
        "end": "мальчик 2?!: “Словите этого говнюка! Он у меня еще получит!”",
        "next": "scene_11_first_trust",
    },
    {
        "file": "scene_11_first_trust.dtl",
        "label": "scene_11_first_trust",
        "title": "Первое доверие",
        "start": "ГГ с девочкой добегают до статуи Фемиды",
        "end": "Сделав буквально пару шагов ГГ развернулся и глядя на Лиру улыбнулся и пошел вперед",
        "next": "scene_12_glade_reveal",
    },
    {
        "file": "scene_12_glade_reveal.dtl",
        "label": "scene_12_glade_reveal",
        "title": "Поляна и раскрытие Лиры",
        "start": "Дойдя до места перед ними открылась небольшая поляна окруженная деревьями, асфальтовые дорожки плавно переходящие в грунтовые",
        "end": "“Там хорошо, никто не против таких как я” - сказала Лира",
        "next": "scene_13_way_home",
    },
    {
        "file": "scene_13_way_home.dtl",
        "label": "scene_13_way_home",
        "title": "Дорога домой",
        "start": "Посидев и поболтав еще немного ГГ смотрит на часы, видя 19:30 встает с камня",
        "end": "Поднявшись еще на 4 этажа выше и дойдя до входной двери в квартиру Лиры",
        "next": "scene_14_lyra_father",
    },
    {
        "file": "scene_14_lyra_father.dtl",
        "label": "scene_14_lyra_father",
        "title": "Отец Лиры",
        "start": "Громкий щелчок замка раздался по лестничной площадке и следом за ним из квартиры Лиры выходит огромный мужчина",
        "end": "“Хорошо, спасибо за предложение и хорошего вам дня” - сказал ГГ",
        "next": "scene_15_home_evening",
    },
    {
        "file": "scene_15_home_evening.dtl",
        "label": "scene_15_home_evening",
        "title": "Дом и вечер",
        "start": "Медленно спускаясь по этажам ГГ не мог поверить во все случившиеся",
        "end": "Съев ужин ГГ отправляется в свою комнату где сразу же валится на кровать и засыпает",
        "next": None,
    },
]


SPEAKER_PREFIXES = [
    "god?",
    "толпа?!",
    "Друг Томас",
    "Дру Томас",
    "девочка?",
    "мальчики?!",
    "девочки?!",
    "мальчик 1?!",
    "мальчик 2?!",
    "Мама?!",
]

ATTRIBUTION_SPEAKERS = [
    ("мысли гг", "ГГ"),
    ("подумал гг", "ГГ"),
    ("сказал гг", "ГГ"),
    ("сказала гг", "ГГ"),
    ("крик гг", "ГГ"),
    ("крикнул гг", "ГГ"),
    ("выкрикнул гг", "ГГ"),
    ("выкрики гг", "ГГ"),
    ("выкрикивает гг", "ГГ"),
    ("прошептал гг", "ГГ"),
    ("промямлил гг", "ГГ"),
    ("ответил гг", "ГГ"),
    ("спросил гг", "ГГ"),
    ("говорит гг", "ГГ"),
    ("тихий восклик гг", "ГГ"),
    ("сказал неуверенно гг", "ГГ"),
    ("начал рассказ гг", "ГГ"),
    ("попытался возразить гг", "ГГ"),
    ("пытается закричать", "ГГ"),
    ("сказала лира", "Лира"),
    ("спросила лира", "Лира"),
    ("ответила лира", "Лира"),
    ("произнесла лира", "Лира"),
    ("высказалась лира", "Лира"),
    ("прошептала лира", "Лира"),
    ("сказала девочка", "Девочка"),
    ("спросила девочка", "Девочка"),
    ("говорит девочка", "Девочка"),
    ("сказал отец", "Отец"),
    ("сказал отце", "Отец"),
    ("спросил отец", "Отец"),
    ("сказал отец лиры", "Отец Лиры"),
    ("сказал элиот", "Элиот"),
]


def load_nonempty_paragraphs(path: Path) -> list[str]:
    doc = Document(path)
    return [p.text.strip() for p in doc.paragraphs if p.text.strip()]


def find_index(paragraphs: list[str], marker: str) -> int:
    try:
        return paragraphs.index(marker)
    except ValueError as exc:
        matches = [idx for idx, text in enumerate(paragraphs) if marker in text]
        if len(matches) == 1:
            return matches[0]
        raise RuntimeError(f"Marker not found: {marker}") from exc


def speaker_line(prefix: str, text: str) -> str:
    if " " in prefix or any(ch in prefix for ch in "?!" ):
        return f'"{prefix}": {text}'
    return f"{prefix}: {text}"


def escape_narration(text: str) -> str:
    return text.replace(":", r"\:")


def split_quote_and_suffix(line: str):
    match = re.match(r'^[\"“](.+?)[\"”]\s*-\s*(.+)$', line)
    if match:
        return match.group(1).strip(), match.group(2).strip()
    return None, None


def transform_line(line: str) -> str:
    if line == "___":
        return ""

    if line in {"Пролог", "Флешбэк", "Выбор заступиться или убежать", "Выбор заступиться", "(Выбор полного имени ГГ)"}:
        return escape_narration(line)

    for prefix in SPEAKER_PREFIXES:
        if line.startswith(prefix + ":"):
            return line

    quote_text, suffix = split_quote_and_suffix(line)
    if quote_text is not None:
        suffix_lower = suffix.lower()
        for pattern, speaker in ATTRIBUTION_SPEAKERS:
            if pattern in suffix_lower:
                normalized_quote = quote_text.strip()
                if normalized_quote.startswith("(") and normalized_quote.endswith(")"):
                    normalized_quote = normalized_quote[1:-1].strip()
                content = f"({normalized_quote})" if "мысли" in suffix_lower or "подумал" in suffix_lower else normalized_quote
                return speaker_line(speaker, content)
        return escape_narration(line)

    return escape_narration(line)


def build_scene_content(label: str, title: str, lines: list[str], next_timeline: str | None) -> str:
    output = [f"label {label} ({title})"]
    for line in lines:
        converted = transform_line(line)
        if converted:
            output.append(converted)
    if next_timeline:
        output.append(f"jump prolog/{next_timeline}")
    return "\n".join(output) + "\n"


def main():
    parser = argparse.ArgumentParser(description="Build Dialogic timelines from the prologue document.")
    parser.add_argument("source", nargs="?", type=Path, default=SOURCE_DOCX,
                        help="Path to the source DOCX (default: docs/Пролог.docx)")
    args = parser.parse_args()
    if not args.source.is_file():
        parser.error(f"Source document not found: {args.source}. Pass the path to your prologue DOCX.")
    paragraphs = load_nonempty_paragraphs(args.source)
    TIMELINE_DIR.mkdir(parents=True, exist_ok=True)

    for scene in SCENES:
        start_idx = find_index(paragraphs, scene["start"])
        end_idx = find_index(paragraphs, scene["end"])
        if end_idx < start_idx:
            raise RuntimeError(f"Scene markers out of order for {scene['file']}")

        scene_lines = paragraphs[start_idx : end_idx + 1]
        content = build_scene_content(scene["label"], scene["title"], scene_lines, scene["next"])
        (TIMELINE_DIR / scene["file"]).write_text(content, encoding="utf-8")

    ROOT_TIMELINE.write_text(
        "label prolog\n"
        "[signal arg=\"open_warehouse_gate_hub\"]\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
