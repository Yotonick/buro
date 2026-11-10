#!/bin/bash
# Сетевой тест игры: хост + 2 клиента начинают смену на полигоне, третий клиент
# подключается, когда смена уже идёт. Проверяется, что у всех один и тот же мир.
# Запуск: game/tests/net_play_test.sh /путь/к/godot
GODOT="${1:-godot}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"
PORT=27992
# BAD_LINK="0.04,0.03,0.05" — прогнать с плохой связью у клиентов (задержка, разброс, потери)
g() { local log=$1; shift; "$GODOT" --headless --path "$DIR" -- --probe --port=$PORT ${BAD_LINK:+--bad-link=$BAD_LINK} "$@" > "$OUT/$log.log" 2>&1 & }
# Вася идёт вперёд и толкает ящики руками, Петю хост отправляет в нокаут (слетает каска),
# хост сам тоже идёт вперёд. Лена подключается на 7-й секунде.
# Хост на 3-й секунде связывает лентой два ящика (Лена увидит это, уже войдя), а Лене,
# когда она поднимет руки, кладёт в руку рулон — она жмёт E и лепит конец ленты к полу.
g host  --host --name=Хост --autostart=3 --walk=1-2.5 --ko=Петя@2 --tape=3 --give=Лена --probe-report=16 --quit-after=18
sleep 1.5
g vasya --join=127.0.0.1 --name=Вася --walk=1-3 --grab=1-3 --probe-report=14.5 --quit-after=16
sleep 0.4
g petya --join=127.0.0.1 --name=Петя --probe-report=14.1 --quit-after=16
sleep 5
g lena  --join=127.0.0.1 --name=Лена --grab=0.5-5 --use=3 --probe-report=9.1 --quit-after=11
wait
echo "--- логи: $OUT"
grep -h -E "KO_DONE|SESSION_ENDED|NET_ERROR|ERROR|SCRIPT" "$OUT"/*.log
python3 - "$OUT" <<'PY'
import json, sys, glob, os
out = sys.argv[1]
rep = {}
for f in sorted(glob.glob(out + "/*.log")):
    name = os.path.basename(f)[:-4]
    for line in open(f, encoding="utf-8", errors="replace"):
        if line.startswith("PROBE "):
            rep[name] = json.loads(line[6:])
fails = []
def check(ok, text):
    print(("PASS  " if ok else "FAIL  ") + text)
    if not ok: fails.append(text)
def near(a, b, tol=0.2):
    return all(abs(x - y) <= tol for x, y in zip(a, b))
check(len(rep) == 4, "все четверо прислали отчёт (%d из 4)" % len(rep))
if len(rep) == 4:
    h = rep["host"]
    check(all(r["scene"].endswith("test_room.tscn") for r in rep.values()), "все на полигоне (включая опоздавшую Лену)")
    check(sorted(h["players"]) == ["Вася", "Лена", "Петя", "Хост"], "на хосте четыре персонажа: " + ", ".join(sorted(h["players"])))
    check(h["players"]["Вася"]["pos"][2] < 3.5, "Вася (клиент) прошёл вперёд: z=%.2f (старт 7)" % h["players"]["Вася"]["pos"][2])
    check(abs(h["players"]["Петя"]["pos"][2] - 7) < 2.5 and abs(h["players"]["Лена"]["pos"][2] - 7) < 0.3, "Петя и Лена остались у старта")
    check(len({p["color"] for p in h["players"].values()}) == 4, "у всех разные цвета")
    for name, r in rep.items():
        if name == "host": continue
        same = sorted(r["players"]) == sorted(h["players"])
        bad = []
        if same:
            for pn, p in h["players"].items():
                q = r["players"][pn]
                if not near(p["pos"], q["pos"]) or not near(p["hand"], q["hand"]) or p["ko"] != q["ko"] or p["helmet"] != q["helmet"] or p["color"] != q["color"]:
                    bad.append(pn)
        check(same and not bad, "%s видит тех же игроков там же, где хост %s" % (name, bad if bad else ""))
        ok = len(r["bodies"]) == len(h["bodies"]) and all(near(a, b) for a, b in zip(h["bodies"], r["bodies"]))
        check(ok, "%s: все %d предметов и стажёры там же, где у хоста" % (name, len(h["bodies"])))
        check(len(h["tapes"]) == 1 and r["tapes"] == h["tapes"], "%s: лента между ящиками та же, что у хоста %s" % (name, r["tapes"]))
        check(r["rolls"] == h["rolls"], "%s: рулоны в том же состоянии, что у хоста %s" % (name, r["rolls"]))
        ok = len(r["helmets"]) == len(h["helmets"]) and all(near(a, b) for a, b in zip(sorted(h["helmets"]), sorted(r["helmets"])))
        check(ok, "%s: слетевшие каски совпадают с хостом (%d)" % (name, len(h["helmets"])))
    # плавность: шаг идущего персонажа за тик должен быть ровным (4.2 м/с / 60 = 0.07 м);
    # рывок — шаг вдвое меньше или в полтора раза больше. Допускаем до 5% (машина теста занята).
    for who, whom in (("petya", "Вася"), ("vasya", "Вася"), ("vasya", "Хост")):
        st = rep[who]["steps"].get(whom)
        check(st is not None and st[0] > 40 and st[1] <= st[0] * 0.05, "%s видит, как идёт %s, без рывков: %s" % (who, whom, st))
    used = [x for x in h["rolls"] if x[1]]
    check(len(used) == 1 and used[0][2] == 0, "Лена (клиент) нажала E — конец ленты прилип к полу: %s" % h["rolls"])
    logs = "".join(open(f, encoding="utf-8", errors="replace").read() for f in glob.glob(out + "/*.log"))
    check("KO_DONE helmets=1" in logs, "нокаут Пети сработал, каска слетела")
    helmets_total = len(h["helmets"]) + sum(1 for p in h["players"].values() if p["helmet"])
    check(helmets_total == 4, "касок в мире ровно четыре (на головах + на полу)")
    check("SCRIPT ERROR" not in logs and "Parse Error" not in logs, "нет ошибок скриптов")
print("RESULT", "PASS" if not fails else "FAILED (%d)" % len(fails))
sys.exit(1 if fails else 0)
PY
