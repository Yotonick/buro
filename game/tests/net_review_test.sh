#!/bin/bash
# Сетевой тест приёмки в «Глубокой тарелке»: хост + клиент, хост заканчивает смену — метрдотель (ускоренный)
# обходит зал; второй клиент входит посреди обхода. После итога у всех должны совпасть: метрдотель
# (виден, стоит у шлюза, та же реплика), звёзды в табличке и сама табличка.
# Запуск: game/tests/net_review_test.sh /путь/к/godot
GODOT="${1:-godot}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"
PORT=27994
g() { local log=$1; shift; "$GODOT" --headless --path "$DIR" -- --probe --port=$PORT ${BAD_LINK:+--bad-link=$BAD_LINK} "$@" > "$OUT/$log.log" 2>&1 & }
g host --host --name=Хост --autostart=2 --map=deep_plate --review=2 --review-report --quit-after=40
sleep 1.5
g vasya --join=127.0.0.1 --name=Вася --review-report --quit-after=40
sleep 9
g lena --join=127.0.0.1 --name=Лена --review-report --probe-report=3 --quit-after=31
wait
echo "--- логи: $OUT"
grep -h -E "SESSION_ENDED|NET_ERROR|SCRIPT" "$OUT"/*.log
python3 - "$OUT" <<'PY'
import json, sys, glob, os
out = sys.argv[1]
rep = {}
for f in sorted(glob.glob(out + "/*.log")):
    name = os.path.basename(f)[:-4]
    rep[name] = [json.loads(l[6:]) for l in open(f, encoding="utf-8", errors="replace") if l.startswith("PROBE ")]
fails = []
def check(ok, text):
    print(("PASS  " if ok else "FAIL  ") + text)
    if not ok: fails.append(text)
fin = {n: r[-1] for n, r in rep.items() if r and "shift" in r[-1] and r[-1]["shift"][0] == 1}
check(len(fin) == 3, "все трое дождались итога приёмки (%d из 3)" % len(fin))
mid = rep.get("lena", [])
if mid and "maitre" in mid[0]:
    check(mid[0]["maitre"][0] and mid[0]["shift"][0] == 3, "Лена вошла посреди обхода: метрдотель в зале, идёт приёмка: %s" % mid[0]["shift"][:2])
else:
    check(False, "Лена прислала отчёт посреди обхода")
if len(fin) == 3:
    h = fin["host"]
    check(h["maitre"][0] and h["shift"][1] == 5 and h["shift"][2] == 5, "у хоста: 5 звёзд, в табличке тоже: %s" % h["shift"])
    for n in ("vasya", "lena"):
        r = fin[n]
        check(r["maitre"][0], "%s видит метрдотеля" % n)
        d = sum((a - b) ** 2 for a, b in zip(r["maitre"][1], h["maitre"][1])) ** 0.5
        check(d < 0.2, "%s: метрдотель там же, где у хоста (%.2f м)" % (n, d))
        check(r["maitre"][3] == h["maitre"][3] and r["maitre"][2] == h["maitre"][2], "%s: та же реплика и лицо: %s" % (n, r["maitre"][3]))
        check(r["shift"][1:] == h["shift"][1:], "%s: те же звёзды и табличка: %s" % (n, r["shift"][1:3]))
logs = "".join(open(f, encoding="utf-8", errors="replace").read() for f in glob.glob(out + "/*.log"))
check("SCRIPT ERROR" not in logs, "нет ошибок скриптов")
check("above the MTU" not in logs, "снимки не больше MTU")
print("RESULT", "PASS" if not fails else "FAILED (%d)" % len(fails))
sys.exit(1 if fails else 0)
PY
