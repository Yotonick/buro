#!/bin/bash
# Сетевой тест «Глубокой тарелки»: хост + клиент начинают смену, второй клиент входит позже.
# Хост прорывает две течи, чинит насос и устраивает скачок в щитке; у всех должны совпасть течи, уровень воды и насос. Потом хост
# возвращает бригаду в лобби — все должны оказаться там.
# Запуск: game/tests/net_plate_test.sh /путь/к/godot
GODOT="${1:-godot}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"
PORT=27993
g() { local log=$1; shift; "$GODOT" --headless --path "$DIR" -- --probe --port=$PORT ${BAD_LINK:+--bad-link=$BAD_LINK} "$@" > "$OUT/$log.log" 2>&1 & }
g host --host --name=Хост --autostart=2 --map=deep_plate --burst=2 --pump=3 --surge=4 --lobby=11 --probe-report=10 --report-after=14.5 --quit-after=16
sleep 1.5
g vasya --join=127.0.0.1 --name=Вася --walk=1-2 --probe-report=9.6 --report-after=14 --quit-after=16
sleep 5
g lena --join=127.0.0.1 --name=Лена --probe-report=4.6 --report-after=8.5 --quit-after=12
wait
echo "--- логи: $OUT"
grep -h -E "SESSION_ENDED|NET_ERROR|SCRIPT|REPORT" "$OUT"/*.log
python3 - "$OUT" <<'PY'
import json, sys, glob, os
out = sys.argv[1]
rep, last = {}, {}
for f in sorted(glob.glob(out + "/*.log")):
    name = os.path.basename(f)[:-4]
    for line in open(f, encoding="utf-8", errors="replace"):
        if line.startswith("PROBE "):
            rep[name] = json.loads(line[6:])
fails = []
def check(ok, text):
    print(("PASS  " if ok else "FAIL  ") + text)
    if not ok: fails.append(text)
check(len(rep) == 3, "все трое прислали отчёт (%d из 3)" % len(rep))
if len(rep) == 3:
    h = rep["host"]
    check(all(r["scene"].endswith("deep_plate.tscn") for r in rep.values()), "все в «Глубокой тарелке» (и опоздавшая Лена)")
    check(sorted(h["players"]) == ["Вася", "Лена", "Хост"], "на хосте три персонажа")
    check(sum(1 for s in h["leaks"] if s != 0) == 2, "у хоста прорвало две течи: %s" % h["leaks"])
    check(h["flood"] > 0.005, "у хоста поднялась вода: %.3f" % h["flood"])
    check(h.get("pump", [0])[0] == 2, "у хоста насос качает: %s" % h.get("pump"))
    bd = h.get("board")
    check(bd is not None and bd[0].count(True) == 2 and not bd[1] and bd[3] == 0, "у хоста скачок: пробка вылетела, рубильник упал: %s" % bd)
    for n in ("vasya", "lena"):
        r = rep[n]
        check(r["leaks"] == h["leaks"], "%s видит те же течи: %s" % (n, r["leaks"]))
        check(r.get("pump") == h.get("pump"), "%s видит тот же насос: %s" % (n, r.get("pump")))
        check(r.get("board") == h.get("board"), "%s видит тот же щиток: %s" % (n, r.get("board")))
        check(abs(r["flood"] - h["flood"]) < 0.02, "%s видит тот же уровень воды: %.3f (у хоста %.3f)" % (n, r["flood"], h["flood"]))
        ok = len(r["bodies"]) == len(h["bodies"]) and all(all(abs(x - y) <= 0.2 for x, y in zip(a, b)) for a, b in zip(h["bodies"], r["bodies"]))
        check(ok, "%s: все %d предметов там же, где у хоста" % (n, len(h["bodies"])))
logs = {os.path.basename(f)[:-4]: open(f, encoding="utf-8", errors="replace").read() for f in glob.glob(out + "/*.log")}
for n, v in logs.items():
    rl = [l for l in v.splitlines() if l.startswith("REPORT ")]
    sc = json.loads(rl[-1][7:])["scene"] if rl else ""
    check(sc.endswith("lobby.tscn"), "%s после смены вернулся в лобби (%s)" % (n, sc))
check("SCRIPT ERROR" not in "".join(logs.values()), "нет ошибок скриптов")
check("above the MTU" not in "".join(logs.values()), "снимки не больше MTU")
print("RESULT", "PASS" if not fails else "FAILED (%d)" % len(fails))
sys.exit(1 if fails else 0)
PY
