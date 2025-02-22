import 'dart:math';
import 'package:flutter/material.dart';
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

class _UnknownGameScreenState extends State<UnknownGameScreen>
    with TickerProviderStateMixin {
  List<String> players = [];
  String currentPlayer = ""; // The player viewing this screen
  String currentRecipient = ""; // The player currently receiving a card
  Map<String, List<Map<String, dynamic>>> playerHands = {};
  List<_AnimatingCard> animatingCards = []; // Cards being animated
  Map<String, Alignment> playerPositions = {}; // Map player names to alignments
  int totalCardsRemaining = 0; // Track total cards left
  int? revealCountdown;

  @override
  void initState() {
    super.initState();
    players = List.from(widget.players);
    _setupSocketListeners();
  }

  @override
  void dispose() {
    for (var card in animatingCards) {
      card.dispose();
    }
    super.dispose();
  }

  void _setupSocketListeners() {
    print("✅ (DEBUG) Reusing existing socket connection!");

    widget.socket.on('player_name', (data) {
      print("👤 (DEBUG) WHO AM I? Received player_name: $data");

      if (mounted) {
        setState(() {
          currentPlayer = data['playerName'];
          print("✅ (DEBUG) WHO AM I? I am: $currentPlayer");

          // Initialize player hands
          for (var player in widget.players) {
            playerHands[player] = [];
          }

          // Map player positions
          _mapPlayerPositions();

          // 📢 Emit distribute_cards after getting player info
          if (currentPlayer == widget.players.first) {
            print(
              "📢 (DEBUG) Emitting distribute_cards for lobby: ${widget.lobbyCode}",
            );
            widget.socket.emit('distribute_cards', {
              'lobbyCode': widget.lobbyCode,
            });
          }
        });
      }
    });

    Future.delayed(Duration(milliseconds: 500), () {
      print("📢 (DEBUG) Requesting player name for lobby: ${widget.lobbyCode}");
      widget.socket.emit('get_player_name', {'lobbyCode': widget.lobbyCode});
    });

    widget.socket.on('receive_card', (data) {
      final card = data['card'];
      final recipient = data['playerName'];

      // Null checks
      if (card == null || recipient == null) {
        print(
          "⚠️ (ERROR) Missing card or playerName in receive_card event: $data",
        );
        return;
      }

      print("🃏 (DEBUG) Card '$card' is being dealt to $recipient");

      // Create an animation controller for the card movement
      final controller = AnimationController(
        duration: Duration(milliseconds: 600),
        vsync: this,
      );

      final alignmentAnimation = AlignmentTween(
        begin: Alignment.center,
        end: playerPositions[recipient] ?? Alignment.center,
      ).animate(CurvedAnimation(parent: controller, curve: Curves.easeInOut));

      // Create animating card (initially face-down)
      final animCard = _AnimatingCard(
        card: card,
        recipient: recipient,
        controller: controller,
        animation: alignmentAnimation,
        vsync: this,
      );

      setState(() {
        animatingCards.add(animCard);
      });

      // Start movement animation
      controller.forward();

      // After reaching the player, add face-down card to hand
      controller.addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() {
            animatingCards.remove(animCard);

            // Add card to player’s hand with isFaceUp = false
            playerHands[recipient]?.add({
              'card': card,
              'isFaceUp': false, // Initially face-down
            });

            print(
              "🂠 (DEBUG) Card '$card' added face-down to $recipient's hand.",
            );
          });

          animCard.dispose(); // Dispose controller after animation
        }
      });
    });

    widget.socket.on('all_cards_sent', (data) {
      final playerName = data['playerName'];
      if (playerName == currentPlayer) {
        print(
          "✅ (DEBUG) All cards received for $playerName. Sending acknowledgment.",
        );
        // Emit acknowledgment back to server with lobbyCode
        widget.socket.emit('cards_received', {
          'playerName': currentPlayer,
          'lobbyCode': widget.lobbyCode,
        });
      }
    });

    widget.socket.on('all_cards_distributed', (data) {
      print("🎉 (DEBUG) All cards distributed. Preparing to flip cards...");

      // Wait 2 seconds, then flip all cards
      Future.delayed(Duration(seconds: 2), () {
        _flipAllCards();
      });
    });

    // 🔥 New listener for card count updates
    widget.socket.on('update_card_count', (data) {
      if (data != null && data['totalCardsRemaining'] != null) {
        setState(() {
          totalCardsRemaining = data['totalCardsRemaining'];
        });
        print(
          "🗃️ (DEBUG) Updated total cards remaining: $totalCardsRemaining",
        );
      }
    });
  }

  void _flipAllCards() async {
    print("🎬 (DEBUG) Flipping only current player's left and right cards...");

    // Start countdown
    setState(() {
      revealCountdown = 2;
    });

    await Future.delayed(Duration(seconds: 1));
    setState(() {
      revealCountdown = 1;
    });

    await Future.delayed(Duration(seconds: 1));
    setState(() {
      revealCountdown = 0; // Show "0" before flipping
    });

    await Future.delayed(Duration(seconds: 1)); // Pause at "0"
    setState(() {
      revealCountdown = null; // Remove countdown text
    });

    // Reveal only left and right cards for current player
    final currentHand = playerHands[currentPlayer];

    if (currentHand != null && currentHand.length >= 3) {
      // Assuming cards are ordered as [left, center, right]
      final leftCardIndex = 0;
      final rightCardIndex = 2;

      // Flip left and right cards face-up
      setState(() {
        currentHand[leftCardIndex]['isFaceUp'] = true;
        currentHand[rightCardIndex]['isFaceUp'] = true;
      });

      print("🔄 (DEBUG) Revealed left and right cards for $currentPlayer");

      // Wait 2 seconds before flipping them back face-down
      await Future.delayed(Duration(seconds: 2));

      setState(() {
        currentHand[leftCardIndex]['isFaceUp'] = false;
        currentHand[rightCardIndex]['isFaceUp'] = false;
      });

      print("🔄 (DEBUG) Flipped back left and right cards for $currentPlayer");
    } else {
      print("⚠️ (DEBUG) Not enough cards to reveal for $currentPlayer");
    }
  }

  /// **Maps player names to screen positions**
  void _mapPlayerPositions() {
    List<String> orderedPlayers = List.from(players);

    // Move current player to bottom
    orderedPlayers.remove(currentPlayer);
    orderedPlayers.insert(0, currentPlayer);

    // Map positions
    playerPositions = {
      orderedPlayers[0]: Alignment.bottomCenter, // Self
      if (orderedPlayers.length > 1) orderedPlayers[1]: Alignment.topCenter,
      if (orderedPlayers.length > 2) orderedPlayers[2]: Alignment.centerLeft,
      if (orderedPlayers.length > 3) orderedPlayers[3]: Alignment.centerRight,
    };

    print("✅ (DEBUG) Player positions mapped: $playerPositions");
  }

  Widget _buildCardFace(String card) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(2, 2)),
        ],
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            card,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildCardBack() {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [Colors.redAccent, Colors.orangeAccent],
          center: Alignment.center,
          radius: 0.75,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Transform.rotate(
            angle: -pi / 4, // Only rotate the "Unknown Bridge" text
            child: Text(
              'Unknown Bridge',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  /// **Renders cards for a specific player**
  List<Widget> _buildPlayerHand(
    String playerName, {
    bool vertical = false,
    double rotateCards = 0,
  }) {
    final hand = playerHands[playerName] ?? [];
    return hand.asMap().entries.map((entry) {
      final index = entry.key;
      final cardData = entry.value;
      final card = cardData['card'];

      return Container(
        width: vertical ? 65 : 45,
        height: vertical ? 45 : 65,
        margin: EdgeInsets.only(
          bottom: vertical ? 4 : 0,
          right: vertical ? 0 : 4,
        ),
        child: RotatedBox(
          quarterTurns: (rotateCards / (pi / 2)).round(),
          child: AnimatedSwitcher(
            duration: Duration(milliseconds: 1500), // Slow down flip animation
            transitionBuilder: (Widget child, Animation<double> animation) {
              final rotate = Tween(begin: pi, end: 0.0).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeInOutBack,
                ), // Smooth curve
              );
              return AnimatedBuilder(
                animation: rotate,
                child: child,
                builder: (context, child) {
                  final isUnder =
                      (ValueKey(_isCardFaceUp(playerName, index)) !=
                          child!.key);
                  final value =
                      isUnder ? min(rotate.value, pi / 2) : rotate.value;
                  return Transform(
                    transform: Matrix4.rotationY(value),
                    alignment: Alignment.center,
                    child: child,
                  );
                },
              );
            },
            layoutBuilder:
                (widget, list) => Stack(children: [widget!, ...list]),
            switchInCurve: Curves.easeInOutBack,
            child:
                _isCardFaceUp(playerName, index)
                    ? _buildCardFace(card)
                    : _buildCardBack(),
          ),
        ),
      );
    }).toList();
  }

  bool _isCardFaceUp(String playerName, int cardIndex) {
    return playerHands[playerName]?[cardIndex]['isFaceUp'] ?? false;
  }

  /// **Builds deck at the center with animating cards**
  Widget _buildCenterDeck() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Deck in the center
        Container(
          width: 45,
          height: 65,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [Colors.redAccent, Colors.orangeAccent],
              center: Alignment.center,
              radius: 0.75,
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black45,
                blurRadius: 4,
                offset: Offset(2, 2),
              ),
            ],
          ),
          child: Center(
            child: Transform.rotate(
              angle: -pi / 4,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Unknown Bridge',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),

        // Animate cards moving to recipients
        ...animatingCards.map((animCard) {
          return AnimatedBuilder(
            animation: animCard.animation,
            builder: (context, child) {
              return Align(
                alignment: animCard.animation.value,
                child: AnimatedBuilder(
                  animation: animCard.flipAnimation,
                  builder: (context, child) {
                    final isFlipped = animCard.flipAnimation.value >= pi / 2;
                    return Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.rotationY(
                        animCard.flipAnimation.value,
                      ),
                      child: Container(
                        width: 45,
                        height: 65,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 4,
                              offset: Offset(2, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child:
                              isFlipped
                                  ? Text(
                                    animCard.card, // Show card face
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                  : _buildCardBack(), // Show card back
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        }).toList(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blueGrey[900],
      body: Stack(
        children: [
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Total Cards Remaining: $totalCardsRemaining',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          // 🎭 Display nameplates and hands for each player
          ...playerPositions.entries.map((entry) {
            String playerName = entry.key;
            Alignment alignment = entry.value;

            bool isBottom = alignment == Alignment.bottomCenter;
            bool isTop = alignment == Alignment.topCenter;
            bool isLeft = alignment == Alignment.centerLeft;
            bool isRight = alignment == Alignment.centerRight;

            return Align(
              alignment: alignment,
              child:
                  isLeft || isRight
                      ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isLeft)
                            Transform.rotate(
                              angle: pi / 2, // Left name rotated 90°
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
                                  playerName,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: _buildPlayerHand(
                              playerName,
                              vertical: true,
                              rotateCards:
                                  isLeft
                                      ? pi / 2
                                      : -pi /
                                          2, // Rotate left/right cards differently
                            ),
                          ),
                          if (isRight)
                            Transform.rotate(
                              angle: -pi / 2, // Right name rotated -90°
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
                                  playerName,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      )
                      : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isTop) // Top Player: Name closest to screen edge, cards below
                          ...[
                            Container(
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
                                playerName,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: _buildPlayerHand(
                                playerName,
                                vertical: false,
                              ),
                            ),
                          ],
                          if (isBottom) // Bottom Player: Cards above, name at bottom
                          ...[
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: _buildPlayerHand(
                                playerName,
                                vertical: false,
                              ),
                            ),
                            Container(
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
                                playerName,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
            );
          }),

          // Center deck and animating cards
          Center(child: _buildCenterDeck()),

          if (revealCountdown != null)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(
                  0.5,
                ), // Slight overlay for focus
                child: Center(
                  child: AnimatedSwitcher(
                    duration: Duration(milliseconds: 500),
                    transitionBuilder: (
                      Widget child,
                      Animation<double> animation,
                    ) {
                      return ScaleTransition(scale: animation, child: child);
                    },
                    child: Text(
                      'REVEALING CARDS IN $revealCountdown',
                      key: ValueKey(
                        revealCountdown,
                      ), // Key for AnimatedSwitcher
                      style: TextStyle(
                        fontFamily: 'Permanent Marker',
                        fontSize: 48,
                        color: Colors.yellowAccent,
                        shadows: [
                          Shadow(
                            blurRadius: 12.0,
                            color: Colors.black,
                            offset: Offset(0, 0),
                          ),
                        ],
                        letterSpacing: 2.0,
                      ),
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

/// Helper class to track animating cards
class _AnimatingCard {
  final String card;
  final String recipient;
  final AnimationController controller;
  final Animation<Alignment> animation;
  late AnimationController flipController;
  late Animation<double> flipAnimation;
  bool isFaceUp = false; // Track if the card is face-up

  _AnimatingCard({
    required this.card,
    required this.recipient,
    required this.controller,
    required this.animation,
    required TickerProvider vsync,
  }) {
    flipController = AnimationController(
      duration: Duration(milliseconds: 500),
      vsync: vsync,
    );
    flipAnimation = Tween<double>(
      begin: 0,
      end: pi,
    ).animate(CurvedAnimation(parent: flipController, curve: Curves.easeInOut));
  }

  void flip() {
    flipController.forward().then((_) {
      isFaceUp = true;
    });
  }

  void dispose() {
    controller.dispose();
    flipController.dispose();
  }
}

class RotationYTransition extends StatelessWidget {
  final Animation<double> turns;
  final Widget child;

  const RotationYTransition({
    Key? key,
    required this.turns,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: turns,
      builder: (context, child) {
        final angle = turns.value * pi;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.rotationY(angle),
          child: child,
        );
      },
      child: child,
    );
  }
}
