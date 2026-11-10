extends RefCounted
## Интерфейс сетевого транспорта. Сейчас реализация одна — ENet (прямое
## подключение по IP, в т.ч. через Radmin VPN). Позже сюда добавляется Steam.

## Создаёт серверный peer. Возвращает null при ошибке (текст — в last_error).
func create_host(_port: int, _max_players: int) -> MultiplayerPeer:
	return null

## Создаёт клиентский peer для подключения к адресу.
func create_client(_address: String, _port: int) -> MultiplayerPeer:
	return null

var last_error := ""
