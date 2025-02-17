import 'package:flutter/material.dart';
import 'dart:math'; // For rotation angles
import 'package:socket_io_client/socket_io_client.dart' as io;

class UnknownGameScreen extends StatefulWidget {
  final String lobbyCode;
  final List<String> players;
  final io.Socket socket;

  const UnknownGameScreen({
    super.key,
    required this.lobbyCode,
    required this.players,
    required this.socket,
  });

  @override
  State<UnknownGameScreen> createState() => _UnknownGameScreenState();
}

class _UnknownGameScreenState extends State<UnknownGameScreen> {
  List<String> players = [];
  String currentPlayer = ""; // The player viewing this screen

  @override
  void initState() {
    super.initState();
    players = List.from(widget.players);
    _setupSocketListeners();
  }

  void _setupSocketListeners() {
    print("✅ (DEBUG) Reusing existing socket connection!");

    widget.socket.on('player_name', (data) {
      print("👤 (DEBUG) WHO AM I? Received player_name: $data");

      if (mounted) {
        setState(() {
          currentPlayer = data['playerName'];
          print("✅ (DEBUG) WHO AM I? I am: $currentPlayer");

          // Ensure correct ordering of players
          _reorderPlayers();
        });
      }
    });

    Future.delayed(Duration(milliseconds: 500), () {
      print("📢 (DEBUG) Requesting player name for lobby: ${widget.lobbyCode}");
      widget.socket.emit('get_player_name', {'lobbyCode': widget.lobbyCode});
    });

    widget.socket.on('start_game', (data) {
      print("🚀 (DEBUG) Received start_game event! Data: $data");

      if (data == null || data['players'] == null) {
        print("⚠️ (DEBUG) start_game data is null or malformed");
        return;
      }

      if (mounted) {
        setState(() {
          players = List<String>.from(data['players']);
          print("✅ (DEBUG) Updated player list after start_game: $players");
          _reorderPlayers();
        });
      }
    });
  }

  /// **Reorders players so that the current player is always at the bottom**
  void _reorderPlayers() {
    if (currentPlayer.isEmpty || !players.contains(currentPlayer)) {
      return; // Safety check
    }

    players.remove(currentPlayer);
    players.insert(0, currentPlayer);

    print("✅ (DEBUG) Player order updated: $players");
  }

  /// **Gets player alignment based on index**
  Alignment getAlignment(int index) {
    switch (index) {
      case 0:
        return Alignment.bottomCenter; // ✅ Self at bottom
      case 1:
        return Alignment.topCenter; // ✅ Player 2 at top
      case 2:
        return Alignment.centerLeft; // ✅ Player 3 on left (rotated)
      case 3:
        return Alignment.centerRight; // ✅ Player 4 on right (rotated)
      default:
        return Alignment.bottomCenter;
    }
  }

  /// **Gets rotation angle for player nameplates**
  double getRotation(int index) {
    switch (index) {
      case 2:
        return pi / 2; // ✅ Left side (90° counterclockwise)
      case 3:
        return -pi / 2; // ✅ Right side (-90° clockwise)
      default:
        return 0; // ✅ No rotation for Top & Bottom
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blueGrey[900],
      body: Stack(
        children: [
          // 🎭 Display nameplates for each player
          for (int i = 0; i < players.length; i++)
            Align(
              alignment: getAlignment(i),
              child: Transform.rotate(
                angle: getRotation(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 20,
                  ),
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    players[i],
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
