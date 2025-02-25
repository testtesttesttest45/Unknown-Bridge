import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
  bool isWheelSpinning = false;
  String? wheelWinner;
  double wheelRotation = 0.0;
  bool showWinnerText = false;
  bool showWheel = true;
  bool showWinnerHighlight = false;
  String currentTurnStatus = "Distributing Cards";
  String? logMessage;
  late AnimationController logMessageController; // For fade-in/out
  late Animation<double> logMessageFadeAnimation;
  String? nextTurnPlayer;
  bool _isDrawing = false; // Prevent multiple draws
  String? _drawnCard; // Holds the drawn card for the current player
  bool _isCardFlipped = false; // Tracks if the card has been flipped
  AnimationController? _deckScaleController; // For scaling animation
  late AnimationController cardEffectController;
  late Animation<double> cardGlowAnimation;
  bool showCardEffect = false;
  List<Map<String, dynamic>> discardedCards = [];

  @override
  void initState() {
    super.initState();
    players = List.from(widget.players);
    _setupSocketListeners();

    // Initialize log message animation
    logMessageController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 500),
    );
    logMessageFadeAnimation = CurvedAnimation(
      parent: logMessageController,
      curve: Curves.easeInOut,
    );

    // Initialize card effect animation (glow)
    cardEffectController = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true); // Looping glow effect

    cardGlowAnimation = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(parent: cardEffectController, curve: Curves.easeInOut),
    );

    // 🔥 Request current game state after a slight delay
    Future.delayed(Duration(milliseconds: 500), () {
      print(
        "📢 (SYNC) Requesting current game state for lobby: ${widget.lobbyCode}",
      );
      widget.socket.emit('request_current_state', {
        'lobbyCode': widget.lobbyCode,
      });
    });

    // Wheel ticker for spinning animation
    Ticker wheelTicker = createTicker((elapsed) {
      if (isWheelSpinning) {
        setState(() {
          wheelRotation += 0.1;
        });
      }
    });
    wheelTicker.start();
  }

  @override
  void dispose() {
    for (var card in animatingCards) {
      card.dispose();
    }
    logMessageController.dispose();
    cardEffectController.dispose();

    if (_deckScaleController != null) {
      _deckScaleController!.dispose();
      _deckScaleController = null; // Nullify after disposal
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

      // Update current turn status to waiting for wheelspin
      setState(() {
        currentTurnStatus = "Waiting for wheelspin";
      });

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

    widget.socket.on('wheelspin_result', (data) {
      final winner = data['winner'];
      final serverPlayers = List<String>.from(data['players']);
      final turnOrder = List<String>.from(data['turnOrder']);

      print("🎉 (CLIENT) Received wheelspin_result | Winner: $winner");
      print("🔄 (CLIENT) Turn order: ${turnOrder.join(', ')}");

      if (winner != null && mounted) {
        setState(() {
          players = serverPlayers;
          isWheelSpinning = true;
          wheelWinner = winner;
          showWinnerText = false;
          showWheel = true;
          showWinnerHighlight = false;
        });

        widget.socket.emit('wheelspin_received', {
          'playerName': currentPlayer,
          'lobbyCode': widget.lobbyCode,
        });

        final localWinner = winner;

        int winnerIndex = players.indexOf(localWinner);
        double segmentAngle = (2 * pi) / players.length;
        double targetRotation = (2 * pi * 5) - (segmentAngle * winnerIndex);

        AnimationController spinController = AnimationController(
          duration: Duration(seconds: 4),
          vsync: this,
        );

        Animation<double> spinAnimation = Tween<double>(
          begin: 0,
          end: targetRotation,
        ).animate(
          CurvedAnimation(parent: spinController, curve: Curves.easeOutCubic),
        );

        spinController.addListener(() {
          setState(() {
            wheelRotation = spinAnimation.value;
          });
        });

        spinController.addStatusListener((status) async {
          if (status == AnimationStatus.completed) {
            print("✅ Wheel spin complete on this client. Winner: $localWinner");

            setState(() {
              isWheelSpinning = false;
              showWinnerText = true;
              showWinnerHighlight = true;
              wheelWinner = localWinner;

              currentTurnStatus = "Current turn: $localWinner";

              int winnerIndex = turnOrder.indexOf(localWinner);
              int nextIndex = (winnerIndex + 1) % turnOrder.length;
              nextTurnPlayer = turnOrder[nextIndex];
            });

            // ✅ First, show the wheelspin winner to everyone
            _showLogMessage("The wheelspin winner is $localWinner");

            // 🔥 Add 2-second delay before hiding the wheel and prompting the winner
            await Future.delayed(Duration(seconds: 2));

            if (mounted) {
              setState(() {
                showWheel = false;
                print("🎯 Wheel closed. Highlighting winner: $localWinner");
              });

              // ✅ Now, only prompt the winner to draw a card
              if (currentPlayer == localWinner) {
                _showLogMessage("Please draw a card from the deck");
              }
            }
          }
        });

        spinController.forward();
      } else {
        print("⚠️ (ERROR) Invalid winner data received: $data");

        widget.socket.emit('request_current_state', {
          'lobbyCode': widget.lobbyCode,
        });
      }
    });

    widget.socket.on('all_acknowledged', (data) {
      final confirmedWinner = data['winner'];
      print(
        "✅ (CLIENT) All players acknowledged. Confirmed winner: $confirmedWinner",
      );

      if (confirmedWinner != null && mounted) {
        setState(() {
          wheelWinner = confirmedWinner;
          showWinnerHighlight = true;
        });
      }
    });

    widget.socket.on('current_game_state', (data) {
      final currentWinner = data['currentWinner'];
      final playersList = List<String>.from(data['players']);

      print("🔄 (SYNC) Current game state received | Winner: $currentWinner");

      if (currentWinner != null && mounted) {
        setState(() {
          players = playersList;
          wheelWinner = currentWinner;
          showWinnerHighlight = true;
        });
      }
    });

    widget.socket.on('broadcast_draw_animation', (data) {
      final playerName = data['playerName'];

      print("📢 (DEBUG) Received draw animation for $playerName");

      if (mounted) {
        setState(() {
          _startCardDrawAnimation();
        });
      }
    });

    widget.socket.on('receive_drawn_card', (data) {
      final card = data['card'];
      final playerName = data['playerName'];

      print("🎉 (DEBUG) Received drawn card: $card for $playerName");

      if (playerName == currentPlayer) {
        setState(() {
          _drawnCard = card;
        });

        // Trigger flip after scaling is complete
        _flipDrawnCard();
      }
    });

    widget.socket.on('card_discarded', (data) {
      final discardedBy = data['playerName'];
      final discardedCard = data['card'];

      print("🗑️ (CLIENT) $discardedBy discarded card: $discardedCard");

      // Generate random rotation between -20 and 20 degrees
      final randomRotation = (Random().nextDouble() * 40 - 20) * (pi / 180);

      if (mounted) {
        setState(() {
          // Add card with random rotation to discarded pile
          discardedCards.add({
            'card': discardedCard,
            'rotation': randomRotation,
          });
        });
      }

      _showLogMessage("$discardedBy discarded $discardedCard");
    });

    widget.socket.on('reset_deck_scale', (data) {
      print("🔄 (CLIENT) Received reset_deck_scale broadcast");

      final discarder = data['playerName'];

      // Play reverse animation for ALL clients
      _safeReverseDeckScale();
    });
  }

  /// **Builds deck at the center with animating cards**
  Widget _buildCenterDeck() {
    bool isCurrentPlayerTurn = currentPlayer == wheelWinner;

    return Stack(
      alignment: Alignment.center,
      children: [
        // Center Deck and Discard Pile in a Row
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Center Deck with Outlined Area
            Container(
              width: 75,
              height: 95,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white38),
              ),
              child: Center(
                child: GestureDetector(
                  onTap:
                      (isCurrentPlayerTurn && !_isDrawing)
                          ? _handleDeckTap
                          : null,
                  child: AnimatedBuilder(
                    animation:
                        _deckScaleController ?? AlwaysStoppedAnimation(0),
                    builder: (context, child) {
                      final scale =
                          1.0 +
                          ((_deckScaleController?.value ??
                                  (_isCardFlipped ? 1.0 : 0)) *
                              1.5);
                      final flip =
                          (_deckScaleController?.value ??
                              (_isCardFlipped ? 1.0 : 0.0)) *
                          pi;
                      final isFlipped = flip >= (pi / 2);

                      return Transform(
                        alignment: Alignment.center,
                        transform:
                            Matrix4.identity()
                              ..scale(scale)
                              ..rotateY(flip),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Glowing effect
                            if (showCardEffect)
                              AnimatedBuilder(
                                animation: cardGlowAnimation,
                                builder: (context, child) {
                                  return Container(
                                    width: 60 * cardGlowAnimation.value,
                                    height: 80 * cardGlowAnimation.value,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.rectangle,
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.yellowAccent
                                              .withOpacity(0.7),
                                          blurRadius: 20,
                                          spreadRadius: 5,
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            // The actual card (face-up or back)
                            Container(
                              width: 45,
                              height: 65,
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  colors: [
                                    Colors.redAccent,
                                    Colors.orangeAccent,
                                  ],
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
                                border:
                                    (isCurrentPlayerTurn && !_isDrawing)
                                        ? Border.all(
                                          color: Colors.yellowAccent,
                                          width: 5,
                                        )
                                        : null,
                              ),
                              child: Center(
                                child:
                                    isFlipped
                                        ? Transform(
                                          alignment: Alignment.center,
                                          transform: Matrix4.rotationY(pi),
                                          child:
                                              _drawnCard != null
                                                  ? _buildCardFace(_drawnCard!)
                                                  : _buildCardBack(),
                                        )
                                        : _buildCardBack(),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

            SizedBox(width: 20), // Space between deck and discard pile
            // Discarded Cards Pile (Fixed next to deck)
            // Discarded Cards Pile (Fixed next to deck)
            Container(
              width: 75,
              height: 95,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white38),
              ),
              child: Stack(
                alignment: Alignment.center,
                children:
                    discardedCards.isNotEmpty
                        ? discardedCards.map((discarded) {
                          return Transform.rotate(
                            angle:
                                discarded['rotation'], // Apply random rotation
                            child: _buildCardFace(discarded['card']),
                          );
                        }).toList()
                        : [
                          Center(
                            child: Text(
                              "Discard Pile",
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
              ),
            ),
          ],
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


  void _handleDiscard() {
    if (_drawnCard == null) return;

    print("🗑️ (CLIENT) Discarding card: $_drawnCard");

    // Send discard event to server with a flag to trigger animation
    widget.socket.emit('discard_card', {
      'lobbyCode': widget.lobbyCode,
      'playerName': currentPlayer,
      'card': _drawnCard,
      'animateReverse': true, // New flag to trigger reverse animation
    });

    // Clear the drawn card and reset UI AFTER reverse animation
    _safeReverseDeckScale();

    setState(() {
      _drawnCard = null; // Clear drawn card
      showCardEffect = false; // Hide glowing border
      _isCardFlipped = false; // Reset card flip
    });

    _showLogMessage("You discarded a card!");
  }

  @override
  Widget build(BuildContext context) {
    // print(
    //   "🔄 Rebuilding UI | Current Winner: $wheelWinner | Highlight: $showWinnerHighlight",
    // );

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
                color: Colors.black.withValues(alpha: 0.7),
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
          Positioned(
            top: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Current Turn Status
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        currentTurnStatus,
                        style: TextStyle(
                          color: Colors.yellowAccent,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (nextTurnPlayer !=
                          null) // ✅ Show next turn if available
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            "Next turn: $nextTurnPlayer",
                            style: TextStyle(
                              color: Colors.grey[300],
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                SizedBox(height: 8),

                // Log Message with Fade Animation
                if (logMessage != null)
                  FadeTransition(
                    opacity: logMessageFadeAnimation,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.yellowAccent.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        logMessage!,
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
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

            bool shouldHighlight =
                (playerName == wheelWinner &&
                    showWinnerHighlight &&
                    !isWheelSpinning);

            // print(
            //   "🎨 Rendering nameplate for $playerName | Highlight: $shouldHighlight",
            // );

            Color nameplateColor =
                shouldHighlight
                    ? Colors.yellowAccent.withValues(alpha: 0.8)
                    : Colors.black.withValues(alpha: 0.7);

            Color textColor = shouldHighlight ? Colors.black : Colors.white;

            return Align(
              alignment: alignment,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // For Top and Bottom positions
                  if (isTop || isBottom) ...[
                    if (isTop)
                      Container(
                        key: ValueKey(
                          "$playerName-${shouldHighlight ? 'highlight' : 'normal'}",
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 20,
                        ),
                        margin: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: nameplateColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          playerName,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: _buildPlayerHand(playerName, vertical: false),
                    ),
                    if (isBottom)
                      Container(
                        key: ValueKey(
                          "$playerName-${shouldHighlight ? 'highlight' : 'normal'}",
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 20,
                        ),
                        margin: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: nameplateColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          playerName,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ),
                  ],

                  // For Left and Right positions
                  if (isLeft || isRight)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isLeft)
                          Transform.rotate(
                            angle: pi / 2,
                            child: Container(
                              key: ValueKey(
                                "$playerName-${shouldHighlight ? 'highlight' : 'normal'}",
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 20,
                              ),
                              margin: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: nameplateColor,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                playerName,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
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
                            rotateCards: isLeft ? pi / 2 : -pi / 2,
                          ),
                        ),
                        if (isRight)
                          Transform.rotate(
                            angle: -pi / 2,
                            child: Container(
                              key: ValueKey(
                                "$playerName-${shouldHighlight ? 'highlight' : 'normal'}",
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 20,
                              ),
                              margin: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: nameplateColor,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                playerName,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            );
          }),

          // Center deck and animating cards
          Center(child: _buildCenterDeck()),

          // Show Discard button if player has drawn a card and it's their turn
          if (showCardEffect &&
              _drawnCard != null &&
              currentPlayer == wheelWinner)
            Positioned(
              bottom: 150,
              left: MediaQuery.of(context).size.width / 2 - 50,
              child: ElevatedButton(
                onPressed: _handleDiscard,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                child: Text(
                  'Discard',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),

          // Reveal countdown
          if (revealCountdown != null)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.5),
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
                      key: ValueKey(revealCountdown),
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

          // Wheel spin UI
          _buildWheelSpin(),
        ],
      ),
    );
  }
}
