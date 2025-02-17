import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class UnknownGameScreen extends StatefulWidget {
  final String lobbyCode;
  final List<String> players;

  const UnknownGameScreen({
    super.key,
    required this.lobbyCode,
    required this.players,
  });

  @override
  State<UnknownGameScreen> createState() => _UnknownGameScreenState();
}

class _UnknownGameScreenState extends State<UnknownGameScreen> {
  List<String> players = [];
  io.Socket? socket;

  @override
  void initState() {
    super.initState();
    players = List.from(widget.players); // Initialize from navigation data
    _connectToSocket();
  }

  void _connectToSocket() {
    print("🔌 Connecting to game server...");

    socket = io.io(
      'http://localhost:3000',
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setReconnectionAttempts(5)
          .setReconnectionDelay(2000)
          .build(),
    );

    socket?.onConnect((_) {
      print("🎉 Connected to game server!");

      // ✅ Ensure we join the correct game lobby
      socket?.emit('join_game', {'lobbyCode': widget.lobbyCode});
    });

    // 🔥 Listen for updates to the lobby state
    socket?.on('lobby_updated', (data) {
      print("📢 Game screen received lobby update: $data");

      if (mounted) {
        setState(() {
          players = List<String>.from(data['players']);
        });

        print("✅ Updated player list in game screen: $players");
      }
    });

    socket?.onDisconnect((_) {
      print("❌ Disconnected from game server.");
    });

    socket?.connect();
  }

  @override
  void dispose() {
    socket?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blueGrey[900],
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Game Started!',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),

            // ✅ Show the list of players
            ...players
                .map(
                  (name) => Text(
                    name,
                    style: const TextStyle(fontSize: 24, color: Colors.white),
                  ),
                )
                .toList(),
          ],
        ),
      ),
    );
  }
}
