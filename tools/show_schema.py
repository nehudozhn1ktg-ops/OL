"""Печатает поля config для плагина по его id."""

import json
import sys
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent.parent / "dsh-config"


def collect(node, found):
    if isinstance(node, dict):
        cond, then = node.get("if"), node.get("then")
        if isinstance(cond, dict) and isinstance(then, dict):
            const = cond.get("properties", {}).get("id", {}).get("const")
            ref = then.get("properties", {}).get("config", {}).get("$ref")
            if const and ref:
                found.setdefault(const, ref)
        for value in node.values():
            collect(value, found)
    elif isinstance(node, list):
        for value in node:
            collect(value, found)


def describe(name: str, node: dict) -> None:
    props = node.get("properties") or {}
    if not props and "anyOf" in node:
        for branch in node["anyOf"]:
            if isinstance(branch, dict) and branch.get("properties"):
                props = branch["properties"]
                break
    print(f"--- {name} ---")
    for key, spec in props.items():
        bits = []
        if "default" in spec:
            bits.append(f"default={spec['default']!r}")
        enum = spec.get("enum") or spec.get("const")
        if enum is not None:
            bits.append(f"values={enum!r}")
        if "items" in spec:
            item = spec["items"]
            inner = json.dumps(item, ensure_ascii=False)[:160]
            bits.append(f"items={inner}")
        print(f"  {key}: {'; '.join(bits) if bits else '-'}")


def main() -> None:
    schema = json.loads((BASE / "schema.txt").read_text(encoding="utf-8"))
    found: dict = {}
    collect(schema, found)
    for target in sys.argv[1:]:
        ref = found.get(target)
        if not ref:
            print(f"--- {target}: нет схемы (есть: {[k for k in found if target[:4] in k][:8]})")
            continue
        describe(target, schema.get("$defs", {}).get(ref.split("/")[-1], {}))


if __name__ == "__main__":
    main()
