#!/bin/bash
# Сетевой дымовой тест: хост + 3 клиента + лишний 5-й на одной машине (headless).
# Запуск: game/tests/net_test.sh /путь/к/godot
GODOT="${1:-godot}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"
PORT=27991
run() { "$GODOT" --headless --path "$DIR" -- "$@" --port=$PORT > "$OUT/$1_$RANDOM.log" 2>&1 & }
"$GODOT" --headless --path "$DIR" -- --host --name=Хост --port=$PORT --report-after=7 --quit-after=12 > "$OUT/host.log" 2>&1 &
sleep 1.5
for n in Вася Вася Петя; do
  "$GODOT" --headless --path "$DIR" -- --join=127.0.0.1 --name=$n --port=$PORT --report-after=6 --quit-after=$([ $n = Петя ] && echo 8 || echo 13) > "$OUT/c_$RANDOM.log" 2>&1 &
  sleep 0.4
done
sleep 1
# пятый — мест нет, должен получить отказ
"$GODOT" --headless --path "$DIR" -- --join=127.0.0.1 --name=Лишний --port=$PORT --quit-after=5 > "$OUT/extra.log" 2>&1 &
# хост после ухода Пети (8 с) должен видеть троих — второй отчёт снимаем отдельным клиентом-наблюдателем не нужно: смотрим отчёт Васи на 10.5 с
wait
echo "--- логи: $OUT"
grep -h -E "REPORT|SESSION_ENDED|NET_ERROR|ERROR|SCRIPT" "$OUT"/*.log
FAIL=0
EXPECT='"players":["Вася 2#2","Вася#1","Петя#3","Хост#0"]'
[ "$(grep -h REPORT "$OUT"/host.log "$OUT"/c_*.log | grep -cF "$EXPECT")" = 4 ] || { echo "FAIL: не все четверо видят одинаковый состав"; FAIL=1; }
grep -q "SESSION_ENDED В бригаде уже нет мест" "$OUT/extra.log" || { echo "FAIL: пятый не получил отказ"; FAIL=1; }
[ "$(grep -l "SESSION_ENDED Хост закрыл" "$OUT"/c_*.log | wc -l)" = 2 ] || { echo "FAIL: клиенты не заметили закрытие хоста"; FAIL=1; }
grep -h -E "SCRIPT ERROR|Parse Error" "$OUT"/*.log && FAIL=1
[ $FAIL = 0 ] && echo "PASS" || echo "FAILED"
exit $FAIL
