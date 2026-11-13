"""Одноразовая правка: путь к навыкам проекта после переезда на C:."""

import re
from pathlib import Path

CONFIG = Path(r"C:\Users\Admin\.dsh\profiles\desktop\cordis.patch.yml")
NEW_PATH = r"C:\Projects\OneLife\skills"


def main() -> None:
    text = CONFIG.read_text(encoding="utf-8")
    pattern = re.compile(r"customSkillDirs:\s*\n(\s*)- '[^']*'")
    match = pattern.search(text)
    if not match:
        print("не нашёл customSkillDirs")
        return
    indent = match.group(1)
    replacement = f"customSkillDirs:\n{indent}- '{NEW_PATH}'"
    replaced = pattern.sub(lambda _m: replacement, text, count=1)
    CONFIG.write_text(replaced, encoding="utf-8", newline="\n")
    check = pattern.search(CONFIG.read_text(encoding="utf-8"))
    print("теперь путь:", check.group(0).splitlines()[-1].strip())


if __name__ == "__main__":
    main()
