import json, sys

a = json.load(open(sys.argv[1], encoding="utf-8"))
b = json.load(open(sys.argv[2], encoding="utf-8"))

diffs = []

def walk(path, x, y):
    if type(x) != type(y):
        # 1 vs 1.0 style: compare by value
        if isinstance(x, (int, float)) and isinstance(y, (int, float)):
            if x != y:
                diffs.append((path, x, y))
            return
        diffs.append((path, x, y)); return
    if isinstance(x, dict):
        for k in sorted(set(x) | set(y)):
            if k not in x: diffs.append((f"{path}.{k}", "<missing-py>", y[k])); continue
            if k not in y: diffs.append((f"{path}.{k}", x[k], "<missing-ts>")); continue
            walk(f"{path}.{k}", x[k], y[k])
    elif isinstance(x, list):
        if len(x) != len(y):
            diffs.append((f"{path}.len", len(x), len(y))); return
        for i, (xi, yi) in enumerate(zip(x, y)):
            walk(f"{path}[{i}]", xi, yi)
    else:
        if x != y:
            diffs.append((path, x, y))

walk("", a, b)

keys = sorted(set(a) | set(b))
print(f"compared {len(keys)} sections: {', '.join(keys)}")
if not diffs:
    print("IDENTICAL — python and typescript agree on every case")
    sys.exit(0)
print(f"\n{len(diffs)} DIFFERENCE(S):")
for path, x, y in diffs[:60]:
    print(f"  {path}\n     py: {x!r}\n     ts: {y!r}")
sys.exit(1)
