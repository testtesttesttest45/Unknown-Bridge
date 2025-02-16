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

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  MainMenuScreenState createState() => MainMenuScreenState();
}

class MainMenuScreenState extends State<MainMenuScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkForPlayerName(); // Ensure settings are loaded first
    });
  }

  Future<void> _checkForPlayerName() async {
    final settingsController = context.read<SettingsController>();
    await settingsController.loadSettings(); // Load settings first

    if (settingsController.playerName.value.isEmpty) {
      // Ensure name is truly empty
      _showNameDialog();
    }
  }

  void _showNameDialog() {
    final settingsController = context.read<SettingsController>();
    final palette = context.read<Palette>(); // Get the color palette
    TextEditingController nameController = TextEditingController();

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: (context, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim1, curve: Curves.easeInOut),
          child: child,
        );
      },
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 320,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: palette.backgroundSettings, // Background from palette
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: palette.pen, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: palette.pen.withValues(alpha: 0.8),
                    blurRadius: 10,
                    spreadRadius: 3,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "What is your name?",
                    style: TextStyle(
                      fontFamily: 'Permanent Marker',
                      fontSize: 24,
                      color: palette.ink, // Text color from palette
                    ),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: nameController,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: palette.inkFullOpacity,
                      fontSize: 18,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: palette.backgroundMain, // Light background
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: palette.pen),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      TextButton(
                        onPressed: () {
                          if (nameController.text.isNotEmpty) {
                            settingsController.setPlayerName(
                              nameController.text,
                            );
                            Navigator.of(context).pop();
                          }
                        },
                        style: TextButton.styleFrom(
                          backgroundColor: palette.pen, // Primary button color
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                        ),
                        child: Text(
                          "OK",
                          style: TextStyle(
                            fontFamily: 'Permanent Marker',
                            fontSize: 20,
                            color: palette.trueWhite, // White text
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          backgroundColor:
                              palette.darkPen, // Darker button color
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                        ),
                        child: Text(
                          "Cancel",
                          style: TextStyle(
                            fontFamily: 'Permanent Marker',
                            fontSize: 20,
                            color: palette.trueWhite,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<Palette>();
    final audioController = context.watch<AudioController>();

    return Scaffold(
      backgroundColor: palette.backgroundMain,
      body: Stack(
        children: [
          // 🎴 Playing Cards Decoration Layer
          Positioned.fill(
            child: CustomPaint(painter: PlayingCardsPainter(palette)),
          ),

          // ⚙️ Settings Icon (Top Right)
          Positioned(
            top: 20,
            right: 20,
            child: IconButton(
              icon: Icon(
                Icons.settings,
                size: 32,
                color: palette.inkFullOpacity,
              ),
              onPressed: () {
                audioController.playSfx(SfxType.buttonTap);
                GoRouter.of(context).push('/settings');
              },
            ),
          ),

          // 🌟 Main UI Elements
          ResponsiveScreen(
            squarishMainArea: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 🏷️ Title Background Overlay (With Rotation)
                  Transform.rotate(
                    angle: -0.1, // Slight rotation
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: palette.ink.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Transform.rotate(
                        angle: 0.1, // Rotate back to keep text readable
                        child: const Text(
                          'Unknown Bridge',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Permanent Marker',
                            fontSize: 55,
                            height: 1,
                            color: Colors.white, // Ensure text stands out
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            rectangularMenuArea: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                MyButton(
                  onPressed: () {
                    audioController.playSfx(SfxType.buttonTap);
                    GoRouter.of(context).go('/play');
                  },
                  child: const Text('Create Party'),
                ),
                _gap,
                MyButton(
                  onPressed: () {
                    audioController.playSfx(SfxType.buttonTap);
                    _showJoinPartyDialog();
                  },
                  child: const Text('Join Party'),
                ),
                _gap,
                const Text('Music by Mr Smith'),
                _gap,
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _gap = SizedBox(height: 10);

  // 🎮 Lobby Dialog for "Join Party"
  void _showJoinPartyDialog() {
    final palette = context.read<Palette>(); // Get the color palette
    TextEditingController partyCodeController = TextEditingController();

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: (context, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim1, curve: Curves.easeInOut),
          child: child,
        );
      },
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 320,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: palette.background4, // Different color from name dialog
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: palette.redPen,
                  width: 3,
                ), // Red border for contrast
                boxShadow: [
                  BoxShadow(
                    color: palette.redPen.withValues(alpha: 0.8), // Darker red
                    blurRadius: 10,
                    spreadRadius: 3,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Enter Party Code",
                    style: TextStyle(
                      fontFamily: 'Permanent Marker',
                      fontSize: 24,
                      color: palette.ink, // Text color from palette
                    ),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: partyCodeController,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: palette.inkFullOpacity,
                      fontSize: 18,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: palette.backgroundMain, // Light background
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: palette.redPen),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      TextButton(
                        onPressed: () {
                          if (partyCodeController.text.isNotEmpty) {
                            GoRouter.of(
                              context,
                            ).go('/play'); // Simulate joining for now
                            Navigator.of(context).pop();
                          }
                        },
                        style: TextButton.styleFrom(
                          backgroundColor:
                              palette.redPen, // Red button for contrast
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                        ),
                        child: Text(
                          "OK",
                          style: TextStyle(
                            fontFamily: 'Permanent Marker',
                            fontSize: 20,
                            color: palette.trueWhite, // White text
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          backgroundColor:
                              palette.darkPen, // Darker button color
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                        ),
                        child: Text(
                          "Cancel",
                          style: TextStyle(
                            fontFamily: 'Permanent Marker',
                            fontSize: 20,
                            color: palette.trueWhite,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// 🎨 Custom Painter for Playing Cards in the Background
class PlayingCardsPainter extends CustomPainter {
  final Palette palette;
  final Random random = Random();

  PlayingCardsPainter(this.palette);

  @override
  void paint(Canvas canvas, Size size) {
    // final cardColors = [
    //   // use a mix of colors, rainbow style
    //   const Color(0xFFE57373), // Red
    //   const Color(0xFFFFD54F), // Yellow
    //   const Color(0xFF4DB6AC), // Teal
    //   const Color(0xFF9575CD), // Purple
    //   const Color(0xFF81C784), // Green
    //   const Color(0xFF64B5F6), // Blue
    //   const Color(0xFFFFB74D), // Orange
    //   const Color(0xFFA1887F), // Brown
    // ];

    final suits = ['♥', '♦', '♣', '♠']; // Hearts, Diamonds, Clubs, Spades
    final values = ['A', '2', '7', 'J', 'Q', 'K']; // Some values for variation

    final paint = Paint();

    // Define restricted areas (title & button sections)
    final double titleHeight = 100;
    final double buttonHeight = 250;

    for (int i = 0; i < 30; i++) {
      double x, y; // double means it can have decimal points
      double width = 50;
      double height = 70;
      double rotation = (random.nextDouble() - 0.5) * 0.6;

      // 🎲 Generate positions, ensuring they are NOT inside restricted areas
      do {
        x = random.nextDouble() * size.width;
        y = random.nextDouble() * size.height;
      } while ((y < titleHeight) || // Avoid Title Area
          (y > size.height - buttonHeight) // Avoid Button Area
          );

      paint.color = Color.fromARGB(
        255,
        random.nextInt(256),
        random.nextInt(256),
        random.nextInt(256),
      );

      // Draw the card background
      canvas.save();
      canvas.translate(x + width / 2, y + height / 2);
      canvas.rotate(rotation);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(0, 0), width: width, height: height),
          const Radius.circular(10),
        ),
        paint,
      );

      // Draw suit & value
      final textPainter = TextPainter(
        text: TextSpan(
          text:
              '${values[random.nextInt(values.length)]}${suits[random.nextInt(suits.length)]}',
          style: TextStyle(
            fontFamily: 'Permanent Marker',
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();
      textPainter.paint(canvas, Offset(-width / 3, -height / 3));

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
