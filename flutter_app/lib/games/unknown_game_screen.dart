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
  Map<String, List<String>> playerHands = {}; // Cards for all players
  List<_AnimatingCard> animatingCards = []; // Cards being animated
  Map<String, Alignment> playerPositions = {}; // Map player names to alignments

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

      // Create an animation controller for the card
      final controller = AnimationController(
        duration: Duration(milliseconds: 600),
        vsync: this,
      );

      final alignmentAnimation = AlignmentTween(
        begin: Alignment.center,
        end: playerPositions[recipient] ?? Alignment.center,
      ).animate(CurvedAnimation(parent: controller, curve: Curves.easeInOut));

      final animCard = _AnimatingCard(
        card: card,
        recipient: recipient,
        controller: controller,
        animation: alignmentAnimation,
      );

      setState(() {
        animatingCards.add(animCard);
      });

      // Start the animation
      controller.forward();

      // After the animation completes
      controller.addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() {
            animatingCards.remove(animCard);
            playerHands[recipient]?.add(card);
          });
          controller.dispose();
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

  /// **Renders cards for a specific player**
  List<Widget> _buildPlayerHand(
    String playerName, {
    bool vertical = false,
    double rotateCards = 0,
  }) {
    final hand = playerHands[playerName] ?? [];
    return hand
        .map(
          (card) => Transform.rotate(
            angle: rotateCards, // 🔥 Rotate cards as needed
            child: Container(
              width: 60, // Fixed width
              height: 90, // Fixed height
              margin:
                  vertical
                      ? EdgeInsets.only(
                        bottom: 2,
                      ) // 🔥 Reduced vertical spacing
                      : EdgeInsets.symmetric(
                        horizontal: 4,
                      ), // Top/Bottom spacing
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 4,
                    offset: Offset(2, 2),
                  ),
                ],
              ),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    card,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        )
        .toList();
  }

  /// **Builds deck at the center with animating cards**
  Widget _buildCenterDeck() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Deck in the center
        Container(
          width: 60,
          height: 90,
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              'Deck',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
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
                child: Container(
                  width: 60,
                  height: 90,
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
                    child: Text(
                      animCard.card,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
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
        ],
      ),
    );
  }
}

/// Helper class to track animating cards
/// Helper class to track animating cards
class _AnimatingCard {
  final String card;
  final String recipient;
  final AnimationController controller;
  final Animation<Alignment> animation;

  _AnimatingCard({
    required this.card,
    required this.recipient,
    required this.controller,
    required this.animation,
  });
}
