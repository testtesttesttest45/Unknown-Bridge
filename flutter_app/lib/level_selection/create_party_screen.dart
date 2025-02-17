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
  String? storedPlayerName;
  bool shouldDeleteParty = true;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ✅ Save the navigation state when the widget is still active
      shouldDeleteParty = ModalRoute.of(context)?.settings.name != '/play';
    });

    final settingsController = context.read<SettingsController>();
    storedPlayerName = settingsController.playerName.value;

    _connectToSocket();
  }

  @override
  void dispose() {
    if (socket != null && socket!.connected) {
      if (shouldDeleteParty) {
        print("📢 Emitting delete_party before disconnecting...");
        socket?.emit('delete_party', {'lobbyCode': lobbyCode});
        socket?.disconnect();
      } else {
        print("🎮 Game started! Keeping socket connected.");
      }
    }
    super.dispose();
  }

  void _connectToSocket() {
    print("🛠 Resetting socket before navigating to Create Party...");

    if (socket != null) {
      if (socket!.connected) {
        socket!.disconnect();
      }
      socket = null;
    }

    socket = io.io(
      'http://localhost:3000',
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setReconnectionAttempts(5)
          .setReconnectionDelay(2000)
          .build(),
    );

    socket?.onConnect((_) {
      print("🎉 Connected to backend");

      if (storedPlayerName != null) {
        socket?.emit('create_party', {'playerName': storedPlayerName});

        if (mounted) {
          setState(() {
            players = [storedPlayerName!];
          });
        }
      }
    });

    socket?.on('party_created', (data) {
      print("🎊 Received party code: ${data['lobbyCode']}");

      if (mounted) {
        setState(() {
          lobbyCode = data['lobbyCode'];
        });
      }
    });

    socket?.on('lobby_updated', (data) {
      print("📢 Host received lobby update: $data");

      if (mounted) {
        setState(() {
          players = List<String>.from(data['players']);
          selectedGame = data['gameMode'] ?? "Unknown";
        });

        print("✅ Players list updated on host screen: $players");
      }
    });

    // 🔥 Listen for `party_closed` and navigate back to main menu
    socket?.on('party_closed', (_) {
      print("❌ Host left, closing lobby...");
      GoRouter.of(context).go('/'); // Navigate to main menu
    });

    socket?.on('start_game', (data) {
      print("🚀 Game has started! Navigating to UnknownGameScreen...");

      shouldDeleteParty = false;

      // ✅ Wait a little before navigating to ensure data is received
      Future.delayed(Duration(milliseconds: 500), () {
        if (mounted) {
          print(
            "🎮 Navigating to game screen with players: ${data['players']}",
          );
          GoRouter.of(context).go(
            '/play',
            extra: {
              'lobbyCode': lobbyCode,
              'players': List<String>.from(data['players']),
              'socket': socket, // ✅ Pass the existing socket!
            },
          );
        }
      });
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
                              if (socket != null && socket!.connected) {
                                socket?.emit('start_game', {
                                  'lobbyCode': lobbyCode,
                                });
                              }
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

            socket = null;
            print("🏠 Navigating back to Main Menu...");
            GoRouter.of(context).go('/');
          },
          child: const Text('Leave'),
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
        if (selectedGame != gameName) {
          setState(() {
            selectedGame = gameName;
          });

          // 🔥 Emit game mode change to the server
          if (socket != null && socket!.connected) {
            print(
              "📢 Emitting change_game_mode: $gameName for lobby $lobbyCode",
            );
            socket?.emit('change_game_mode', {
              'lobbyCode': lobbyCode,
              'gameMode': gameName,
            });
          }
        }
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
      height: 40, // 👈 Fixed height for uniform row thickness
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
            index < players.length ? players[index] : 'Waiting...',
            style: TextStyle(
              fontFamily: 'Permanent Marker',
              fontSize: 18,
              color:
                  index < players.length ? palette.inkFullOpacity : Colors.grey,
            ),
          ),

          // 👇 Maintain spacing consistency
          SizedBox(
            width: 32, // Matches IconButton size
            child:
                index < players.length && players[index] != storedPlayerName
                    ? GestureDetector(
                      onTap: () {
                        _kickPlayer(players[index]);
                      },
                      child: Icon(
                        Icons.remove_circle,
                        color: palette.redPen,
                        size: 24, // 👈 Adjust size for correct placement
                      ),
                    )
                    : const SizedBox(), // Keeps spacing even if button isn't shown
          ),
        ],
      ),
    );
  }

  void _kickPlayer(String playerName) {
    if (socket != null && socket!.connected) {
      socket?.emit('kick_player', {
        'lobbyCode': lobbyCode,
        'playerName': playerName,
      });
    }
  }
}
