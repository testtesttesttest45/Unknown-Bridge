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

class CreatePartyScreen extends StatefulWidget {
  const CreatePartyScreen({super.key});

  @override
  State<CreatePartyScreen> createState() => _CreatePartyScreenState();
}

class _CreatePartyScreenState extends State<CreatePartyScreen> {
  String selectedGame = "Unknown"; // Default game selection
  List<String> players = []; // Player list (for now, only self)

  @override
  void initState() {
    super.initState();
    _initializeLobby(); // Populate lobby with current player
  }

  void _initializeLobby() {
    final settingsController = context.read<SettingsController>();
    setState(() {
      players.add(settingsController.playerName.value); // Add self to lobby
    });
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

                  // 🏷️ Placeholder Lobby Code
                  Text(
                    'Lobby Code: 1234',
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
                    onPressed: players.length < 4
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
          bottom: index == 3
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
