import 'dart:async' show Completer;

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

import 'dart:math';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  MainMenuScreenState createState() => MainMenuScreenState();
}

class MainMenuScreenState extends State<MainMenuScreen> {
  List<CardData> cardPositions = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkForPlayerName(); // Ensure settings are loaded first
      _generateCardPositions(); // ✅ Now runs after the first frame
    });
  }

  void _generateCardPositions() {
    final random = Random();
    final suits = ['♥', '♦', '♣', '♠'];
    final values = [
      'A',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      '10',
      'J',
      'Q',
      'K',
    ];

    final screenSize = MediaQuery.of(context).size;
    final double titleHeight = 100;
    final double buttonHeight = 250;

    for (int i = 0; i < 30; i++) {
      double x, y;
      do {
        x = random.nextDouble() * screenSize.width;
        y = random.nextDouble() * screenSize.height;
      } while ((y < titleHeight) || (y > screenSize.height - buttonHeight));

      String suit = suits[random.nextInt(suits.length)];
      String value = values[random.nextInt(values.length)];

      Color randomBackgroundColor = Color.fromARGB(
        255,
        random.nextInt(256),
        random.nextInt(256),
        random.nextInt(256),
      ); // ✅ Fully random color

      Color suitColor =
          (suit == '♥' || suit == '♦')
              ? Colors.red
              : Colors.black; // ✅ Separate suit color

      cardPositions.add(
        CardData(
          x: x,
          y: y,
          width: 50,
          height: 70,
          rotation: (random.nextDouble() - 0.5) * 0.6,
          color: randomBackgroundColor, // ✅ Card background is now fully random
          suit: suit,
          value: value,
          suitColor: suitColor, // ✅ Store suit color separately
        ),
      );
    }

    setState(() {}); // ✅ Ensure the UI updates
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
    final palette = context.read<Palette>();
    TextEditingController nameController = TextEditingController();

    showGeneralDialog(
      context: context,
      barrierDismissible: false, // 🚫 Prevent dismissing the dialog
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
                color: palette.backgroundSettings,
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
                      color: palette.ink,
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
                      fillColor: palette.backgroundMain,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: palette.pen),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () {
                      if (nameController.text.isNotEmpty) {
                        settingsController.setPlayerName(nameController.text);
                        Navigator.of(context).pop();
                      }
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: palette.pen,
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
                        color: palette.trueWhite,
                      ),
                    ),
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
          // 🎴 Playing Cards Decoration Layer (Now Cached)
          Positioned.fill(
            child: CustomPaint(
              painter: PlayingCardsPainter(palette, cardPositions),
            ),
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 30,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: palette.ink.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Transform.rotate(
                      angle: 0.1,
                      child: const Text(
                        'Unknown Bridge',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Permanent Marker',
                          fontSize: 55,
                          height: 1,
                          color: Colors.white,
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
                    GoRouter.of(context).go('/create-party');
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
    final palette = context.read<Palette>();
    TextEditingController partyCodeController = TextEditingController();
    String? errorMessage;

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
          child: StatefulBuilder(
            builder: (context, setState) {
              return Material(
                color: Colors.transparent,
                child: Container(
                  width: 320,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: palette.background4,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: palette.redPen, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: palette.redPen.withValues(alpha: 0.8),
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
                          color: palette.ink,
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
                          fillColor: palette.backgroundMain,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: palette.redPen),
                          ),
                        ),
                      ),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          errorMessage!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 16,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          TextButton(
                            onPressed: () async {
                              if (partyCodeController.text.isNotEmpty) {
                                bool isValid = await _attemptJoinLobby(
                                  partyCodeController.text,
                                );
                                if (isValid) {
                                  Navigator.of(
                                    context,
                                  ).pop(); // ✅ Close before navigating
                                  GoRouter.of(context).go(
                                    '/join-party/${partyCodeController.text}',
                                  );
                                } else {
                                  setState(() {
                                    errorMessage = "❌ Lobby does not exist!";
                                  });
                                }
                              }
                            },
                            style: TextButton.styleFrom(
                              backgroundColor: palette.redPen,
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
                                color: palette.trueWhite,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: TextButton.styleFrom(
                              backgroundColor: palette.darkPen,
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
              );
            },
          ),
        );
      },
    );
  }

  Future<bool> _attemptJoinLobby(String lobbyCode) async {
    final completer = Completer<bool>();
    bool hasResponded = false; // ✅ Prevent duplicate responses

    final tempSocket = io.io(
      'http://localhost:3000',
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setReconnectionAttempts(1)
          .setReconnectionDelay(500)
          .build(),
    );

    tempSocket.onConnect((_) {
      if (!hasResponded) {
        print("🔍 Verifying lobby existence: $lobbyCode");
        tempSocket.emit('check_lobby_exists', {'lobbyCode': lobbyCode});
      }
    });

    tempSocket.on('lobby_valid', (_) {
      if (!hasResponded) {
        hasResponded = true;
        print("✅ Lobby exists! Allowing navigation.");
        completer.complete(true);
        tempSocket.disconnect();
      }
    });

    tempSocket.on('invalid_lobby', (_) {
      if (!hasResponded) {
        hasResponded = true;
        print("❌ Lobby does not exist!");
        completer.complete(false);
        tempSocket.disconnect();
      }
    });

    Future.delayed(const Duration(seconds: 1), () {
      if (!hasResponded) {
        hasResponded = true;
        completer.complete(false);
        tempSocket
            .dispose(); // ✅ Properly dispose socket without causing UI rebuilds
      }
    });

    tempSocket.connect();
    return completer.future;
  }
}

// 🎨 Custom Painter for Playing Cards in the Background (No Animations)
class PlayingCardsPainter extends CustomPainter {
  final Palette palette;
  final List<CardData> cardPositions;

  PlayingCardsPainter(this.palette, this.cardPositions);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    for (var card in cardPositions) {
      // ✅ Ensure card background is fully random
      paint.color = card.color;

      // 🃏 Draw the card background
      canvas.save();
      canvas.translate(card.x + card.width / 2, card.y + card.height / 2);
      canvas.rotate(card.rotation);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(0, 0),
            width: card.width,
            height: card.height,
          ),
          const Radius.circular(10),
        ),
        paint,
      );

      // 🎴 Use stored suit color (Red for ♥♦, Black for ♣♠)
      final suitPainter = TextPainter(
        text: TextSpan(
          text: card.suit,
          style: TextStyle(
            fontFamily: 'Permanent Marker',
            fontSize: 18,
            color: card.suitColor, // ✅ Uses stored suit color (Red or Black)
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      // 🎨 Value (Always white)
      final valuePainter = TextPainter(
        text: TextSpan(
          text: card.value,
          style: const TextStyle(
            fontFamily: 'Permanent Marker',
            fontSize: 18,
            color: Colors.white, // ✅ Value is always white
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      // Layout and paint text
      suitPainter.layout();
      valuePainter.layout();

      // Paint value above the suit
      valuePainter.paint(canvas, Offset(-card.width / 3, -card.height / 3));
      suitPainter.paint(
        canvas,
        Offset(-card.width / 3 + 14, -card.height / 3),
      ); // Shift suit slightly right

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// 🎴 Data class to store card positions and details
class CardData {
  final double x, y, width, height, rotation;
  final Color color; // ✅ Background color (fully random)
  final String suit, value;
  final Color suitColor; // ✅ Separate suit color (red or black)

  CardData({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.rotation,
    required this.color, // ✅ Random background color
    required this.suit,
    required this.value,
    required this.suitColor, // ✅ Separate suit color
  });
}
