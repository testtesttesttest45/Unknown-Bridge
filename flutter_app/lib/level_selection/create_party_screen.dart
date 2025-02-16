import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../audio/audio_controller.dart';
import '../audio/sounds.dart';
import '../settings/settings.dart';
import '../style/my_button.dart';
import '../style/palette.dart';
import '../style/responsive_screen.dart';
import 'dart:math';
import 'package:socket_io_client/socket_io_client.dart' as io;

class CreatePartyScreen extends StatefulWidget {
  const CreatePartyScreen({super.key});

  @override
  State<CreatePartyScreen> createState() => _CreatePartyScreenState();
}

class _CreatePartyScreenState extends State<CreatePartyScreen> {
  String selectedGame = "Unknown";
  List<String> players = [];
  String lobbyCode = "----";
  io.Socket? socket; // Socket for multiplayer

  @override
  void initState() {
    super.initState();
    _initializeLobby(); // Populate lobby with current player
    _connectToSocket();
  }

  @override
  void dispose() {
    if (socket != null && socket!.connected) {
      print("📢 Emitting delete_party before disconnecting...");
      socket?.emit('delete_party', {'lobbyCode': lobbyCode});
      socket?.disconnect();
    }
    socket = null; // Reset for safety

    super.dispose();
  }

  void _initializeLobby() {
    final settingsController = context.read<SettingsController>();
    setState(() {
      players.add(settingsController.playerName.value); // Add self to lobby
    });
  }

  void _connectToSocket() {
    print("🛠 Resetting socket before navigating to Create Party...");

    // Ensure previous socket instance is safely disconnected before reinitializing
    if (socket != null) {
      if (socket!.connected) {
        socket!.disconnect();
      }
      socket = null; // Reset before creating a new instance
    }

    // ✅ Safely initialize socket instance
    final newSocket = io.io(
      'http://localhost:3000', // Change to actual server URL if needed
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setReconnectionAttempts(5)
          .setReconnectionDelay(2000)
          .build(),
    );

    // ✅ Assign `newSocket` before setting listeners
    socket = newSocket;

    // ✅ Use `?.` to prevent accessing socket before it's ready
    socket?.onConnect((_) {
      print("🎉 Connected to backend");

      final settingsController = context.read<SettingsController>();
      final playerName = settingsController.playerName.value;

      socket?.emit('create_party', {
        'playerName': playerName, // Send player name to server
      });
    });

    socket?.on('party_created', (data) {
      print("🎊 Received party code: ${data['lobbyCode']}");
      if (mounted) {
        setState(() {
          lobbyCode = data['lobbyCode'];
        });
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
    final audioController = context.watch<AudioController>();

    return Scaffold(
      backgroundColor: palette.backgroundLevelSelection, // Themed background
      body: ResponsiveScreen(
        squarishMainArea: Column(
          children: [
            const SizedBox(height: 20),
            // 🃏 Title: "Create Party"
            const Text(
              'Create Party',
              style: TextStyle(
                fontFamily: 'Permanent Marker',
                fontSize: 40,
                height: 1,
              ),
            ),
            const SizedBox(height: 30),

            // 🎮 Game Mode Selection (Unknown / Bridge)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _gameOptionButton('Unknown'),
                const SizedBox(width: 20),
                _gameOptionButton('Bridge'),
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
                  // 📌 Players Count
                  Text(
                    '${players.length}/4 Players',
                    style: TextStyle(
                      fontFamily: 'Permanent Marker',
                      fontSize: 20,
                      color: palette.inkFullOpacity,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 🏷️ Dynamic Lobby Code
                  Text(
                    'Lobby Code: $lobbyCode', // 🔥 Dynamic lobby code
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
                  const SizedBox(height: 20),

                  // 🤖 Add Bots Button
                  MyButton(
                    onPressed: () {
                      // For now, this button doesn't do anything
                    },
                    child: const Text('Add Bots'),
                  ),
                  const SizedBox(height: 10),

                  // 🚀 Start Button (Disabled until 4 players join)
                  MyButton(
                    onPressed:
                        players.length < 4
                            ? null // Disabled if players < 4
                            : () {
                              audioController.playSfx(SfxType.buttonTap);
                              GoRouter.of(context).go('/play'); // Go to game
                            },
                    child: const Text('Start'),
                  ),
                ],
              ),
            ),
          ],
        ),

        // 🔙 Back Button
        rectangularMenuArea: MyButton(
          onPressed: () {
            print("🔙 Back button pressed! Disconnecting socket...");
            if (socket != null && socket!.connected) {
              socket?.emit('delete_party', {'lobbyCode': lobbyCode});
              socket?.disconnect();
            }

            socket = null; // Ensure a fresh instance next time
            print("🏠 Navigating back to Main Menu...");
            GoRouter.of(context).go('/');
          },
          child: const Text('Back'),
        ),
      ),
    );
  }

  // 🎮 Game Selection Button with Scaling and Image
  Widget _gameOptionButton(String gameName) {
    final palette = context.read<Palette>();
    final bool isSelected = gameName == selectedGame;

    return GestureDetector(
      onTap: () {
        setState(() {
          selectedGame = gameName;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300), // Smooth transition
        curve: Curves.easeInOut,
        width: isSelected ? 160 : 120, // Scale up selected button
        height: isSelected ? 180 : 140, // Scale up image too
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
              width: isSelected ? 90 : 70,
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
      ),
    );
  }

  // 🎭 Lobby Table Row
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
          // Show player name if exists, otherwise leave blank
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
