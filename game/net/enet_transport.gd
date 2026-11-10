extends "res://net/net_transport.gd"
## ENet: один игрок хостит, остальные подключаются по IP (Radmin VPN / LAN).

func create_host(port: int, max_players: int) -> MultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	# Два запасных соединения сверх состава: лишний игрок должен успеть
	# получить понятный отказ «мест нет», а не молчаливый таймаут.
	var err := peer.create_server(port, max_players - 1 + 2)
	if err != OK:
		last_error = "Не удалось открыть порт %d (возможно, игра уже запущена или порт занят)." % port
		return null
	return peer

func create_client(address: String, port: int) -> MultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		last_error = "Некорректный адрес: %s" % address
		return null
	return peer
