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
  bool _canInteractWithDeck = false; // Controls deck interactivity
  bool _showSkipButton = false;
  bool _hasSelectedDeck = false;
  bool _hasSelectedDiscard = false;
  bool _showUndoSelection = false;
  bool _isSelectingReplacement =
      false; // Indicates if the player is choosing a replacement card
  int? _selectedReplacementIndex;
  bool _canDiscard =
      false; // 🔒 Prevents discard before animation is fully done
  bool _animationCompleted = false;
  bool _canCurrentPlayerReplace = false;

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

              _canInteractWithDeck = true;
              _showSkipButton = true;

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

    widget.socket.on('next_turn', (data) {
      final newCurrentPlayer = data['currentPlayer'];
      final upcomingPlayer = data['nextPlayer'];

      print(
        "➡️ (CLIENT) It's now $newCurrentPlayer's turn. Next up: $upcomingPlayer",
      );

      if (mounted) {
        setState(() {
          wheelWinner = newCurrentPlayer; // Highlight current player
          _canCurrentPlayerReplace = false; // Reset for all players
          showWinnerHighlight = true;
          currentTurnStatus = "Current turn: $newCurrentPlayer";
          nextTurnPlayer = upcomingPlayer;

          _isDrawing = false; // ✅ Reset drawing state for new turn
          _drawnCard = null; // ✅ Reset drawn card
          showCardEffect = false; // ✅ Hide discard effect

          _isSelectingReplacement =
              false; // ✅ Reset selection state for new turn
          _selectedReplacementIndex = null; // ✅ Clear selected index
          _showSkipButton =
              (newCurrentPlayer ==
                  currentPlayer); // ✅ Show Skip button only for the current player

          // 🔥 Fix: Reset selection flags to ensure yellow outline is visible again
          _hasSelectedDeck = false;
          _hasSelectedDiscard = false;
          _showUndoSelection = false;

          if (currentPlayer == newCurrentPlayer) {
            _showLogMessage("It's your turn! Draw or pick a card.");
          }
        });
      }
    });

    widget.socket.on('show_log_message', (data) {
      final message = data['message'];

      if (message != null && mounted) {
        print("📢 (CLIENT) Log Message: $message");
        _showLogMessage(message); // 🔥 Show message to all players
      }
    });

    widget.socket.on('reset_discarded_card', (data) {
      if (mounted) {
        setState(() {
          for (var card in discardedCards) {
            card['isSelected'] = false;
          }
        });

        print("🔄 (CLIENT) Reset discarded card zoom for all players.");
      }
    });

    widget.socket.on('highlight_discarded_card', (data) {
      final selectedCard = data['card'];

      if (selectedCard != null && mounted) {
        setState(() {
          for (var card in discardedCards) {
            card['isSelected'] = card['card'] == selectedCard;
          }
        });

        print(
          "🃏 (CLIENT) Highlighting selected discarded card: $selectedCard",
        );
      }
    });

    widget.socket.on('update_replaced_card', (data) {
      String playerName = data['playerName'];
      int replaceIndex = data['replaceIndex'];
      String newCard = data['newCard'];
      bool wasDrawnFromDeck =
          data['wasDrawnFromDeck'] ?? false; // ✅ Default to false

      if (playerHands.containsKey(playerName)) {
        setState(() {
          playerHands[playerName]![replaceIndex] = {
            'card':
                (playerName == currentPlayer || !wasDrawnFromDeck)
                    ? newCard // ✅ Show value to owner, but not others if from deck
                    : "???", // ✅ Hide from others
            'isFaceUp': !wasDrawnFromDeck, // ✅ Hide if drawn from deck
          };
        });

        print(
          "🔄 (CLIENT) Updated replaced card for $playerName at index $replaceIndex (From Deck: $wasDrawnFromDeck)",
        );
      }
    });

    widget.socket.on('flip_card_back', (data) {
      String playerName = data['playerName'];
      int replaceIndex = data['replaceIndex'];
      bool wasDrawnFromDeck = data['wasDrawnFromDeck'] ?? false;

      if (playerHands.containsKey(playerName)) {
        setState(() {
          _triggerCardFlip(
            playerName,
            replaceIndex,
            false,
          ); // ✅ Flip card face down
        });

        print(
          "🔄 (CLIENT) Flipped back replaced card for $playerName at index $replaceIndex (Was from Deck: $wasDrawnFromDeck)",
        );
      }
    });
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
      final isFaceUp = cardData['isFaceUp'];

      bool isCurrentPlayer = playerName == currentPlayer;
      bool isSelectable =
          isCurrentPlayer &&
          _isSelectingReplacement &&
          _drawnCard != null; // ✅ Allow replacement

      return GestureDetector(
        onTap:
            isSelectable
                ? () => _handleReplaceCard(index)
                : null, // ✅ Allow replacing
        child: Container(
          width: vertical ? 65 : 45,
          height: vertical ? 45 : 65,
          margin: EdgeInsets.only(
            bottom: vertical ? 4 : 0,
            right: vertical ? 0 : 4,
          ),
          decoration: BoxDecoration(
            border:
                isSelectable
                    ? Border.all(
                      color: Colors.yellowAccent,
                      width: 3,
                    ) // ✅ Highlight for replacement
                    : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: RotatedBox(
            quarterTurns: (rotateCards / (pi / 2)).round(),
            child: AnimatedSwitcher(
              duration: Duration(milliseconds: 800),
              transitionBuilder: (Widget child, Animation<double> animation) {
                final rotateAnim = Tween(begin: pi, end: 0.0).animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeInOut),
                );
                return AnimatedBuilder(
                  animation: rotateAnim,
                  child: child,
                  builder: (context, child) {
                    final isUnder = (ValueKey(isFaceUp) != child!.key);
                    var tilt =
                        isUnder
                            ? min(rotateAnim.value, pi / 2)
                            : rotateAnim.value;
                    return Transform(
                      transform: Matrix4.rotationY(tilt),
                      alignment: Alignment.center,
                      child: child,
                    );
                  },
                );
              },
              layoutBuilder:
                  (widget, list) => Stack(children: [widget!, ...list]),
              switchInCurve: Curves.easeInOut,
              child:
                  isFaceUp
                      ? _buildCardFace(card, key: ValueKey('face_$card'))
                      : _buildCardBack(key: ValueKey('back_$card')),
            ),
          ),
        ),
      );
    }).toList();
  }

  void _handleReplaceCard(int replaceIndex) {
    if (_drawnCard == null) return;

    String replacedCard = playerHands[currentPlayer]![replaceIndex]['card'];
    bool wasDrawnFromDeck =
        !_hasSelectedDiscard; // ✅ True if picked from center deck

    print(
      "🔄 (CLIENT) $currentPlayer replacing card at index $replaceIndex ($replacedCard) with $_drawnCard",
    );

    setState(() {
      playerHands[currentPlayer]![replaceIndex]['card'] = _drawnCard!;
    });

    // Emit replacement event to server
    widget.socket.emit('replace_card', {
      'lobbyCode': widget.lobbyCode,
      'playerName': currentPlayer,
      'replacedCard': replacedCard,
      'newCard': _drawnCard,
      'replaceIndex': replaceIndex,
      'wasDrawnFromDeck': wasDrawnFromDeck, // ✅ Send this flag to server
    });

    // ✅ Flip the replaced card back to face-down after a delay for **all players**
    Future.delayed(Duration(seconds: 2), () {
      widget.socket.emit('flip_card_back', {
        'lobbyCode': widget.lobbyCode,
        'playerName': currentPlayer,
        'replaceIndex': replaceIndex,
        'wasDrawnFromDeck':
            wasDrawnFromDeck, // ✅ Send this flag to ensure proper flip
      });
    });

    // ✅ Ensure the deck scale reset only happens if the deck was used
    if (!_hasSelectedDiscard) {
      widget.socket.emit('reset_deck_scale', {'lobbyCode': widget.lobbyCode});
    }

    // Reset interaction states
    setState(() {
      _drawnCard = null;
      _isCardFlipped = false;
      showCardEffect = false;
      _isSelectingReplacement = false;
      _selectedReplacementIndex = null;
      _hasSelectedDiscard = false;
      _hasSelectedDeck = false;
      _showUndoSelection = false;
      _canInteractWithDeck = true;
    });

    _showLogMessage("$currentPlayer replaced $replacedCard with a new card.");
  }

  void _handleDeckTap() {
    if (_isDrawing || !_canInteractWithDeck) return;

    print("🎯 (DEBUG) Deck tapped by $currentPlayer");

    setState(() {
      _isDrawing = true;
      _canInteractWithDeck = false;
      _hasSelectedDeck = true;
      _hasSelectedDiscard = false;
      _showSkipButton = false;
      _showUndoSelection = false;
      _isSelectingReplacement = true;

      // 🔥 Reset discard state at the start of each turn
      _animationCompleted = false;
      _canDiscard = false;
    });

    widget.socket.emit('reset_discarded_card', {'lobbyCode': widget.lobbyCode});
    widget.socket.emit('draw_card', {
      'lobbyCode': widget.lobbyCode,
      'playerName': currentPlayer,
    });

    _startCardDrawAnimation();
  }

  /// **Builds deck at the center with animating cards**
  Widget _buildCenterDeck() {
    bool isCurrentPlayerTurn = currentPlayer == wheelWinner;
    bool canTapDeck =
        isCurrentPlayerTurn && !_isDrawing && _canInteractWithDeck;

    return Stack(
      alignment: Alignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 🎴 Center Deck
            GestureDetector(
              onTap: canTapDeck ? _handleDeckTap : null,
              child: Container(
                width: 75,
                height: 95,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white38),
                ),
                child: Center(
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
                            // ✅ Only the current player sees the glow effect
                            if (showCardEffect && isCurrentPlayerTurn)
                              AnimatedBuilder(
                                animation: cardGlowAnimation,
                                builder: (context, child) {
                                  return Container(
                                    width: 60 * cardGlowAnimation.value,
                                    height: 80 * cardGlowAnimation.value,
                                    decoration: BoxDecoration(
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
                                    isCurrentPlayerTurn &&
                                            !_hasSelectedDeck &&
                                            !_hasSelectedDiscard
                                        ? Border.all(
                                          color: Colors.yellowAccent,
                                          width: 4, // ✅ Thin external outline
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

            SizedBox(width: 20),

            // 🗑️ Discard Pile
            GestureDetector(
              onTap:
                  (discardedCards.isNotEmpty &&
                          currentPlayer == wheelWinner &&
                          !_hasSelectedDeck)
                      ? () => _handleDiscardedCardTap(discardedCards.last)
                      : null,
              child: Container(
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
                          ? discardedCards.asMap().entries.map((entry) {
                            final index = entry.key;
                            final discarded = entry.value;
                            final isTopCard =
                                index == discardedCards.length - 1;

                            return AnimatedScale(
                              scale:
                                  isTopCard
                                      ? (discarded['isSelected'] == true
                                          ? 2.0
                                          : 1.0)
                                      : 1.0,
                              duration: Duration(milliseconds: 300),
                              child: Transform.rotate(
                                angle: discarded['rotation'],
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border:
                                        isTopCard &&
                                                isCurrentPlayerTurn &&
                                                !_hasSelectedDeck &&
                                                !_hasSelectedDiscard
                                            ? Border.all(
                                              color: Colors.yellowAccent,
                                              width:
                                                  4, // ✅ Thin external outline
                                            )
                                            : null,
                                  ),
                                  child: _buildCardFace(discarded['card']),
                                ),
                              ),
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
            ),
          ],
        ),
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
                                    animCard.card,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                  : _buildCardBack(),
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

  void _handleSkipTurn() {
    if (currentPlayer != wheelWinner)
      return; // ✅ Ensure only the current player can click Skip

    print("🚫 (CLIENT) $currentPlayer skipped their turn");

    setState(() {
      _showSkipButton = false; // ✅ Hide Skip button after clicking

      // 🔥 Reset discarded card zoom
      for (var card in discardedCards) {
        card['isSelected'] = false;
      }
    });

    // Broadcast the reset to ALL clients
    widget.socket.emit('reset_discarded_card', {'lobbyCode': widget.lobbyCode});

    // Emit skip turn event
    widget.socket.emit('skip_turn', {
      'lobbyCode': widget.lobbyCode,
      'playerName': currentPlayer,
    });

    _showLogMessage("$currentPlayer skipped their turn.");
  }

  void _startCardDrawAnimation() {
    print("🎬 (DEBUG) Starting enhanced draw animation");

    _deckScaleController = AnimationController(
      duration: Duration(milliseconds: 500),
      vsync: this,
    );

    _deckScaleController!.addListener(() {
      setState(() {
        if (_deckScaleController!.value >= 1) {
          _isCardFlipped = true;
        }
      });
    });

    _deckScaleController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        print("✅ (DEBUG) Scaling and flipping complete.");

        setState(() {
          _isCardFlipped = true;
          showCardEffect = true;
          _animationCompleted = true;
        });

        // 🔒 Delay enabling discard button slightly to prevent instant clicking
        Future.delayed(Duration(milliseconds: 1500), () {
          if (mounted) {
            setState(() {
              _canDiscard = true;

              _canCurrentPlayerReplace =
                  (currentPlayer == wheelWinner) ? true : false;
            });
          }
        });

        // ✅ Now, only after the flip animation completes, allow card replacement
        Future.delayed(Duration(milliseconds: 1500), () {
          if (mounted) {
            setState(() {
              _isSelectingReplacement =
                  true; // ✅ Enable replacement interaction **only after flip**
            });
          }
        });

        if (currentPlayer == wheelWinner) {
          _showLogMessage("Discard or Replace your card!");
        }
      }
    });

    _deckScaleController!.forward();
  }

  @override
  Widget build(BuildContext context) {
    bool isCurrentPlayerTurn = currentPlayer == wheelWinner;
    bool canTapDeck =
        isCurrentPlayerTurn && !_isDrawing && _canInteractWithDeck;
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
          // Show Skip Turn button before drawing, then show Discard button after drawing
          Positioned(
            bottom: 150,
            left: MediaQuery.of(context).size.width / 2 - 100,
            child: Row(
              children: [
                if (_showSkipButton && currentPlayer == wheelWinner)
                  ElevatedButton(
                    onPressed: _handleSkipTurn,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                      padding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                    child: Text("Skip Turn", style: TextStyle(fontSize: 18)),
                  ),
                if (_showUndoSelection) SizedBox(width: 10),
                if (_showUndoSelection)
                  ElevatedButton(
                    onPressed: _handleUndoSelection,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey,
                      padding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                    child: Text(
                      "Undo Selection",
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
              ],
            ),
          ),

          // Show Discard button if player has drawn a card and it's their turn
          if (showCardEffect &&
              _drawnCard != null &&
              _isCardFlipped &&
              _canDiscard &&
              _animationCompleted && // ✅ Ensures button only appears after full animation
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