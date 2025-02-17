import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../audio/audio_controller.dart';
import '../audio/sounds.dart';
import '../settings/settings.dart';
import '../style/my_button.dart';
import '../style/palette.dart';
import '../style/responsive_screen.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class JoinPartyScreen extends StatefulWidget {
  final String lobbyCode;
  const JoinPartyScreen({super.key, required this.lobbyCode});

  @override
  State<JoinPartyScreen> createState() => _JoinPartyScreenState();
}

class _JoinPartyScreenState extends State<JoinPartyScreen> {
  String selectedGame = "Unknown";
  List<String> players = [];
  io.Socket? socket;
  String? storedPlayerName;

  @override
  void initState() {
    super.initState();

    // ✅ Store player name when the widget is first initialized
    final settingsController = context.read<SettingsController>();
    storedPlayerName = settingsController.playerName.value;

    _connectToLobby();
  }

  @override
  void dispose() {
    if (socket != null && socket!.connected) {
      print("📢 Emitting leave_lobby before disconnecting...");
      socket?.emit('leave_lobby', {
        'lobbyCode': widget.lobbyCode,
        'playerName': storedPlayerName,
      });
      socket?.disconnect();
    }

    socket = null; // Reset the socket instance
    super.dispose();
  }

  void _connectToLobby() {
    print("🛠 Connecting to existing lobby: ${widget.lobbyCode}");

    socket = io.io(
      'http://localhost:3000',
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setReconnectionAttempts(5)
          .setReconnectionDelay(2000)
          .build(),
    );

    socket?.onConnect((_) {
      print("🎉 Connected to backend as joiner");

      if (storedPlayerName != null) {
        socket?.emit('join_party', {
          'lobbyCode': widget.lobbyCode,
          'playerName': storedPlayerName,
        });
      }
    });

    socket?.on('lobby_updated', (data) {
      print("📢 Joiner received updated lobby state: $data");

      if (mounted) {
        setState(() {
          players = List<String>.from(data['players']);
          selectedGame = data['gameMode'] ?? "Unknown";
        });
      }
    });

    socket?.on('party_closed', (_) {
      print("❌ Host left, closing lobby...");

      socket?.disconnect(); // ✅ Ensure socket is disconnected first
      socket = null;
      if (mounted) {
        GoRouter.of(context).go('/');
      }
    });
    socket?.on('player_kicked', (data) {
      if (data['playerName'] == storedPlayerName) {
        print("❌ You were removed by the creator.");

        if (mounted) {
          GoRouter.of(context).go('/');
          showDialog(
            context: context,
            builder:
                (context) => AlertDialog(
                  title: Text("Removed from Lobby"),
                  content: Text("You were removed by the creator."),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text("OK"),
                    ),
                  ],
                ),
          );
        }
      }
    });

    socket?.onConnectError((err) {
      print("⚠️ Socket connection error: $err");
    });

    socket?.onDisconnect((_) {
      print("❌ Disconnected from backend");
    });

    print("🔌 Attempting to connect to socket...");
    socket?.connect();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<Palette>();

    return Scaffold(
      backgroundColor: palette.backgroundLevelSelection,
      body: ResponsiveScreen(
        squarishMainArea: Column(
          children: [
            const SizedBox(height: 20),
            const Text(
              'Join Party',
              style: TextStyle(
                fontFamily: 'Permanent Marker',
                fontSize: 40,
                height: 1,
              ),
            ),
            const SizedBox(height: 30),

            // 🎮 Game Mode Selection (Disabled for joiners)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _gameOptionButton('Unknown', enabled: false),
                const SizedBox(width: 20),
                _gameOptionButton('Bridge', enabled: false),
              ],
            ),
            const SizedBox(height: 40),

            // 📋 Lobby Info Section
            Container(
              width: 320,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: palette.backgroundMain,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: palette.ink, width: 3),
              ),
              child: Column(
                children: [
                  Text(
                    '${players.length}/4 Players',
                    style: TextStyle(
                      fontFamily: 'Permanent Marker',
                      fontSize: 20,
                      color: palette.inkFullOpacity,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 🏷️ Show lobby code
                  Text(
                    'Lobby Code: ${widget.lobbyCode}',
                    style: TextStyle(
                      fontFamily: 'Permanent Marker',
                      fontSize: 24,
                      color: palette.pen,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 👥 Players List Table
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: palette.ink, width: 2),
                    ),
                    child: Column(
                      children: List.generate(
                        4,
                        (index) => _lobbyPlayerRow(index),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        // 🔙 Back Button
        rectangularMenuArea: MyButton(
          onPressed: () {
            print("🔙 Back button pressed! Leaving lobby...");
            if (socket != null && socket!.connected) {
              socket?.emit('leave_lobby', {
                'lobbyCode': widget.lobbyCode,
                'playerName': storedPlayerName,
              });
              socket?.disconnect();
            }

            socket = null;
            print("🏠 Navigating back to Main Menu...");
            GoRouter.of(context).go('/');
          },
          child: const Text('Leave'),
        ),
      ),
    );
  }

  Widget _gameOptionButton(String gameName, {required bool enabled}) {
    final palette = context.read<Palette>();
    final bool isSelected = gameName == selectedGame;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300), // ✅ Smooth transition
      curve: Curves.easeInOut,
      width: isSelected ? 160 : 120, // ✅ Scale animation
      height: isSelected ? 180 : 140, // ✅ Scale animation
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isSelected ? palette.pen : palette.backgroundMain,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.ink, width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            gameName,
            style: TextStyle(
              fontFamily: 'Permanent Marker',
              fontSize: 20,
              color: isSelected ? Colors.white : palette.inkFullOpacity,
            ),
          ),
          const SizedBox(height: 8),
          // 🖼️ Game Image (Scales with Selection)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            width: isSelected ? 90 : 70, // ✅ Image scales with selection
            height: isSelected ? 90 : 70,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              image: DecorationImage(
                image: AssetImage(
                  gameName == "Bridge"
                      ? 'images/bridge.png'
                      : 'images/unknown.png',
                ),
                fit: BoxFit.cover,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lobbyPlayerRow(int index) {
    final palette = context.read<Palette>();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom:
              index == 3
                  ? BorderSide.none
                  : BorderSide(color: palette.ink, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            index < players.length ? players[index] : '',
            style: TextStyle(
              fontFamily: 'Permanent Marker',
              fontSize: 18,
              color: palette.inkFullOpacity,
            ),
          ),
        ],
      ),
    );
  }
}
