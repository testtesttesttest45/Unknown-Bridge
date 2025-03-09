const express = require('express');
const { createServer } = require('http');
const socketIo = require('socket.io');

const app = express();
const server = createServer(app);
const io = socketIo(server, {
    cors: {
        origin: '*', // Allow all origins for development
        methods: ['GET', 'POST'],
    }
});

// Store active lobbies
const lobbies = {};
const ongoingDistributions = {};
let totalCardsInDeck = 0;
const acknowledgedClientsPerLobby = {};

// Function to log active lobbies
const logActiveLobbies = () => {
    const activeLobbies = Object.keys(lobbies);
    console.log(`Active lobbies: ${activeLobbies.length > 0 ? `${activeLobbies.length} (${activeLobbies.join(', ')})` : 'None'}`);
};

io.on('connection', (socket) => {
    console.log(`A user connected: ${socket.id}`);

    socket.on('create_party', (data) => {
        const playerName = data.playerName || "Unknown"; // Default if missing

        let lobbyCode;
        do {
            lobbyCode = Math.floor(1000 + Math.random() * 9000).toString();
        } while (lobbies[lobbyCode]);

        // Store lobby with the host player
        lobbies[lobbyCode] = {
            host: socket.id,
            hostName: playerName, // Store player name
            players: [{ id: socket.id, name: playerName }],
            gameMode: "Unknown" // Default game mode
        };

        // ✅ Creator joins the room immediately
        socket.join(lobbyCode);

        console.log(`🎊 Lobby created: ${lobbyCode} by ${socket.id} (${playerName})`);
        console.log(`📢 Active lobbies: ${Object.keys(lobbies).length} (${Object.keys(lobbies).join(", ")})`);

        // Send the generated lobby code back to the creator
        socket.emit('party_created', { lobbyCode });

        // ✅ Immediately send `lobby_updated` to the creator
        io.to(lobbyCode).emit('lobby_updated', {
            players: lobbies[lobbyCode].players.map(p => p.name),
            gameMode: lobbies[lobbyCode].gameMode
        });
    });

    socket.on('join_party', (data) => {
        const { lobbyCode, playerName } = data;

        if (!lobbies[lobbyCode]) {
            console.log(`❌ Lobby ${lobbyCode} does not exist.`);
            socket.emit('invalid_lobby'); // ❌ Send response to client
            return;
        }

        // ✅ Remove any previous instance of the player before re-adding
        lobbies[lobbyCode].players = lobbies[lobbyCode].players.filter(p => p.name !== playerName);

        // ✅ Add the new player with a fresh socket ID
        lobbies[lobbyCode].players.push({ id: socket.id, name: playerName });

        console.log(`👤 ${playerName} joined lobby ${lobbyCode}`);

        // ✅ Join the socket room for real-time updates
        socket.join(lobbyCode);

        // ✅ Emit updated lobby state to all players
        io.to(lobbyCode).emit('lobby_updated', {
            players: lobbies[lobbyCode].players.map(p => p.name),
            gameMode: lobbies[lobbyCode].gameMode || "Unknown",
        });

        // ✅ Notify only the joiner that they successfully joined
        socket.emit('lobby_join_success', { lobbyCode });
    });


    socket.on('check_lobby_exists', (data) => {
        const { lobbyCode } = data;

        if (!lobbies[lobbyCode]) {
            console.log(`❌ Lobby ${lobbyCode} does not exist.`);
            socket.emit('invalid_lobby'); // ❌ Notify client
        } else {
            console.log(`✅ Lobby ${lobbyCode} exists.`);
            socket.emit('lobby_valid'); // ✅ Notify client
        }
    });

    socket.on('kick_player', (data) => {
        const { lobbyCode, playerName } = data;

        if (!lobbies[lobbyCode] || lobbies[lobbyCode].host !== socket.id) {
            console.log(`❌ Unauthorized kick request for ${lobbyCode}`);
            return;
        }

        const playerIndex = lobbies[lobbyCode].players.findIndex(p => p.name === playerName);
        if (playerIndex !== -1) {
            const kickedPlayer = lobbies[lobbyCode].players.splice(playerIndex, 1);
            console.log(`👢 ${playerName} was kicked from lobby ${lobbyCode}`);

            io.to(lobbyCode).emit('lobby_updated', {
                players: lobbies[lobbyCode].players.map(p => p.name),
                gameMode: lobbies[lobbyCode].gameMode
            });

            io.to(kickedPlayer[0].id).emit('player_kicked', { playerName });
        }
    });


    socket.on('change_game_mode', (data) => {
        const { lobbyCode, gameMode } = data;

        if (!lobbies[lobbyCode] || lobbies[lobbyCode].host !== socket.id) {
            console.log(`❌ Invalid game mode change request for ${lobbyCode}`);
            return;
        }

        if (!gameMode) {
            console.log(`⚠️ Received NULL game mode change request for ${lobbyCode}, ignoring`);
            return;
        }

        lobbies[lobbyCode].gameMode = gameMode;

        console.log(`🎮 Game mode changed to ${gameMode} for lobby ${lobbyCode}`);

        // 🔥 Emit updated lobby state to all players
        io.to(lobbyCode).emit('lobby_updated', {
            players: lobbies[lobbyCode].players.map(p => p.name),
            gameMode: gameMode,
        });
    });

    socket.on('leave_lobby', (data) => {
        const { lobbyCode, playerName } = data;

        if (!lobbies[lobbyCode]) {
            console.log(`❌ Lobby ${lobbyCode} does not exist.`);
            return;
        }

        // ✅ Don't remove players if the game has started
        if (lobbies[lobbyCode].inGame) {
            console.log(`⚠️ ${playerName} tried to leave, but game is active.`);
            return;
        }

        // Remove player from the lobby
        const playerIndex = lobbies[lobbyCode].players.findIndex(p => p.name === playerName);
        if (playerIndex !== -1) {
            lobbies[lobbyCode].players.splice(playerIndex, 1);
            console.log(`👋 ${playerName} left lobby ${lobbyCode}`);
        }

        // Delete the lobby only if it's empty **and not in-game**
        if (lobbies[lobbyCode].players.length === 0 && !lobbies[lobbyCode].inGame) {
            console.log(`🔥 Lobby ${lobbyCode} deleted as it is now empty.`);
            delete lobbies[lobbyCode];
            return;
        }

        // Notify all players in the lobby about the updated state
        io.to(lobbyCode).emit('lobby_updated', {
            players: lobbies[lobbyCode].players.map(p => p.name),
            gameMode: lobbies[lobbyCode].gameMode
        });
    });


    socket.on('delete_party', (data) => {
        const { lobbyCode } = data;

        if (lobbies[lobbyCode]) {
            console.log(`🔥 Deleting lobby: ${lobbyCode}`);

            // 🔥 Notify all players in the lobby that the party is closing
            io.to(lobbyCode).emit('party_closed');

            // Remove lobby from server storage
            delete lobbies[lobbyCode];
        }
    });

    socket.on('disconnect', () => {
        console.log(`❌ A user disconnected: ${socket.id}`);

        // Remove player from any lobbies
        for (const [code, lobby] of Object.entries(lobbies)) {
            const playerIndex = lobby.players.findIndex(p => p.id === socket.id);
            if (playerIndex !== -1) {
                const playerName = lobby.players[playerIndex].name;
                lobby.players.splice(playerIndex, 1);
                console.log(`👋 Player ${playerName} (${socket.id}) left lobby ${code}`);

                // If lobby is empty, delete it
                if (lobby.players.length === 0) {
                    console.log(`🔥 Lobby ${code} deleted.`);
                    delete lobbies[code];
                }
            }
        }
    });

    socket.on('start_game', (data) => {
        const { lobbyCode } = data;

        if (!lobbies[lobbyCode] || lobbies[lobbyCode].host !== socket.id) {
            console.log(`❌ Unauthorized game start request for lobby ${lobbyCode}`);
            return;
        }

        console.log(`🚀 Game starting for lobby ${lobbyCode}`);
        console.log(`📢 Current players in lobby ${lobbyCode}:`,
            lobbies[lobbyCode].players.map(p => p.name)
        );

        // ✅ Mark the lobby as in-game to prevent accidental deletion
        lobbies[lobbyCode].inGame = true;

        // 🔥 Extra logging to see if each player is receiving `start_game`
        lobbies[lobbyCode].players.forEach((player) => {
            console.log(`🎯 Sending start_game to player: ${player.name} (ID: ${player.id})`);

            io.to(player.id).emit('start_game', {
                players: lobbies[lobbyCode].players.map(p => p.name),
            });
        });

        // ✅ Ensure that the player list is properly updated for everyone
        io.to(lobbyCode).emit('lobby_updated', {
            players: lobbies[lobbyCode].players.map(p => p.name),
            gameMode: lobbies[lobbyCode].gameMode
        });
    });

    socket.on('get_player_name', (data) => {
        const { lobbyCode } = data;

        if (!lobbies[lobbyCode]) {
            console.log(`❌ (DEBUG) Lobby ${lobbyCode} does not exist.`);
            return;
        }

        const player = lobbies[lobbyCode].players.find(p => p.id === socket.id);

        if (player) {
            console.log(`📢 (DEBUG) Sending player name to ${socket.id}: ${player.name}`);

            // ✅ FIX for `socket.io@2.4.1`: Check if the socket is still connected
            if (io.sockets.connected[socket.id]) {
                socket.emit('player_name', { playerName: player.name });
            } else {
                console.log(`⚠️ (DEBUG) Player ${player.name} (${socket.id}) disconnected before receiving name.`);
            }
        } else {
            console.log(`⚠️ (DEBUG) Player ID ${socket.id} not found in lobby ${lobbyCode}`);
        }
    });

    socket.on('cards_received', async (ackData) => {
        const { lobbyCode, playerName } = ackData;

        console.log(`📨 Received acknowledgment from ${playerName} for lobby ${lobbyCode}`);

        // Check if the distribution exists
        if (!ongoingDistributions[lobbyCode]) {
            console.log(`⚠️ No active distribution found for lobby ${lobbyCode}`);
            console.trace("Trace for missing distribution:");
            return;
        }

        const distribution = ongoingDistributions[lobbyCode];
        const expectedPlayer = distribution.players[distribution.currentPlayerIndex]?.name;

        if (playerName === expectedPlayer) {
            console.log(`✅ ${playerName} received all cards.`);

            distribution.currentPlayerIndex++;

            if (distribution.currentPlayerIndex < distribution.players.length) {
                const nextPlayer = distribution.players[distribution.currentPlayerIndex];
                console.log(`➡️ Moving to next player: ${nextPlayer.name}`);
                await new Promise(resolve => setTimeout(resolve, 500)); // Short delay before next player
                await distribution.distributeToPlayer(nextPlayer);
            } else {
                console.log("✅ All cards distributed.");
                console.log("🃏 Cards distributed:", distribution.cardsDistributed);

                // 🔥 Notify all clients that all cards are distributed
                io.to(lobbyCode).emit('all_cards_distributed', { lobbyCode });

                // Clean up AFTER all players have received cards
                if (ongoingDistributions[lobbyCode]) {
                    delete ongoingDistributions[lobbyCode];
                    console.log(`🗑️ Cleared distribution state for lobby ${lobbyCode}`);
                } else {
                    console.log(`⚠️ Tried to delete non-existing distribution for lobby ${lobbyCode}`);
                }
            }
        } else {
            console.log(`⚠️ Received unexpected acknowledgment from ${playerName}, expected ${expectedPlayer}`);
        }
    });

    socket.on('distribute_cards', async (data) => {
        const { lobbyCode } = data;
    
        if (!lobbies[lobbyCode]) {
            console.log(`❌ Lobby ${lobbyCode} does not exist.`);
            return;
        }
    
        const deck = shuffleDeck(createDeck());
        totalCardsInDeck = deck.length;
    
        // ✅ Store deck in lobbies
        lobbies[lobbyCode].deck = deck;
    
        const players = lobbies[lobbyCode].players;
    
        // ✅ Reinitialize playerHands for new game
        lobbies[lobbyCode].playerHands = {};
        const cardsDistributed = {};
    
        // Initialize empty hands for all players
        players.forEach(player => {
            lobbies[lobbyCode].playerHands[player.name] = []; // ✅ Ensure hands are initialized
            cardsDistributed[player.name] = [];
        });
    
        let currentPlayerIndex = 0;
    
        // Store distribution state globally
        ongoingDistributions[lobbyCode] = {
            currentPlayerIndex,
            players,
            cardsDistributed,
            deck,
            async distributeToPlayer(player) {
                const playerId = player.id;
                const playerName = player.name;
    
                console.log(`📢 Distributing cards to ${playerName}`);
    
                for (let i = 0; i < 3; i++) {
                    const card = this.deck.pop();
                    totalCardsInDeck--;
    
                    // console.log(`🃏 Dealt card '${card}' to ${playerName}`);
                    console.log(`🗃️ Total cards remaining: ${totalCardsInDeck}`);
    
                    // ✅ Store card in playerHands
                    lobbies[lobbyCode].playerHands[playerName].push(card);
                    this.cardsDistributed[playerName].push(card);
    
                    // Emit card to player
                    io.to(lobbyCode).emit('receive_card', { card, playerName });
    
                    // 🔥 Emit updated card count to all clients
                    io.to(lobbyCode).emit('update_card_count', {
                        totalCardsRemaining: totalCardsInDeck
                    });
    
                    await new Promise(resolve => setTimeout(resolve, 300)); // Short delay between cards
                }
    
                // Notify player that all cards have been sent
                io.to(playerId).emit('all_cards_sent', { playerName });
            }
        };
    
        console.log(`🚀 Started card distribution for lobby ${lobbyCode}`);
        console.log(`🎮 Players: ${players.map(p => p.name).join(', ')}`);
    
        // Start distributing to the first player
        await ongoingDistributions[lobbyCode].distributeToPlayer(players[currentPlayerIndex]);
    
        // ✅ Log all player hands after distribution
        logCurrentHands(lobbyCode);
    });

    socket.on('spin_wheel', (data) => {
        const { lobbyCode } = data;

        if (!lobbies[lobbyCode]) {
            console.log(`❌ Lobby ${lobbyCode} does not exist.`);
            return;
        }

        const isHost = lobbies[lobbyCode].players[0].id === socket.id;
        if (!isHost) return;

        const players = lobbies[lobbyCode].players.map(p => p.name);
        const winner = players[Math.floor(Math.random() * players.length)];

        const winnerIndex = players.indexOf(winner);
        const turnOrder = players.slice(winnerIndex).concat(players.slice(0, winnerIndex));

        // ✅ Persist winner in the lobby state
        lobbies[lobbyCode].currentWinner = winner;
        lobbies[lobbyCode].turnOrder = turnOrder;
        lobbies[lobbyCode].turnIndex = 0;

        console.log(`🎉 (SERVER) The winner of the wheelspin is: ${winner}`);
        console.log(`🔄 (SERVER) New turn order: ${turnOrder.join(', ')}`);

        // Initialize acknowledgment tracking BEFORE broadcasting
        acknowledgedClientsPerLobby[lobbyCode] = new Set();

        // Emit wheelspin_result to all clients
        io.to(lobbyCode).emit('wheelspin_result', {
            winner,
            players,
            turnOrder
        });
    });

    // ✅ Move acknowledgment listener globally
    socket.on('wheelspin_received', ({ playerName, lobbyCode }) => {
        // Check if acknowledgment tracking exists
        if (!acknowledgedClientsPerLobby[lobbyCode]) {
            console.log(`⚠️ (SERVER) No active wheelspin acknowledgment for lobby ${lobbyCode}`);
            return;
        }

        // Add player to acknowledged set
        acknowledgedClientsPerLobby[lobbyCode].add(playerName);
        console.log(`✅ (SERVER) ${playerName} acknowledged wheelspin_result`);

        const totalPlayers = lobbies[lobbyCode]?.players.length || 0;

        // When all players have acknowledged
        if (acknowledgedClientsPerLobby[lobbyCode].size === totalPlayers) {
            console.log(`✅ (SERVER) All players acknowledged the wheelspin.`);
            io.to(lobbyCode).emit('all_acknowledged', {
                winner: lobbies[lobbyCode].currentWinner
            });

            // Clean up acknowledgment tracking
            delete acknowledgedClientsPerLobby[lobbyCode];
        }
    });

    // Handle state synchronization requests
    socket.on('request_current_state', (data) => {
        const { lobbyCode } = data;
        const lobby = lobbies[lobbyCode];

        if (lobby) {
            socket.emit('current_game_state', {
                currentWinner: lobby.currentWinner || null,
                players: lobby.players.map(p => p.name),
            });
        }
    });

    socket.on('draw_card', (data) => {
        const { lobbyCode, playerName } = data;

        if (!lobbies[lobbyCode]) {
            console.log(`❌ Lobby ${lobbyCode} does not exist.`);
            return;
        }

        const lobby = lobbies[lobbyCode];

        // Prevent multiple draws
        if (lobby.hasDrawnCard) {
            console.log(`⚠️ ${playerName} attempted multiple draws. Ignored.`);
            return;
        }

        lobby.hasDrawnCard = true; // Lock further draws

        const deck = lobby.deck;

        if (!deck || deck.length === 0) {
            console.log("⚠️ Deck is empty!");
            return;
        }

        const drawnCard = deck.pop();
        console.log(`🃏 ${playerName} drew card: ${drawnCard}`);

        // Notify all players about the draw animation
        io.to(lobbyCode).emit('broadcast_draw_animation', {
            playerName,
        });

        // Send the drawn card to the player after scaling completes
        setTimeout(() => {
            const player = lobby.players.find(p => p.name === playerName);
            if (player) {
                io.to(player.id).emit('receive_drawn_card', { card: drawnCard, playerName });
            }

            // Update total cards remaining
            io.to(lobbyCode).emit('update_card_count', {
                totalCardsRemaining: deck.length,
            });

            // Reset draw lock after turn completes
            setTimeout(() => {
                lobby.hasDrawnCard = false;
            }, 1000); // Allow next draw after a delay
        }, 1200); // Match scaling duration
    });

    socket.on('discard_card', (data) => {
        const { lobbyCode, playerName, card, animateReverse } = data;

        if (!lobbies[lobbyCode]) {
            console.log(`❌ Lobby ${lobbyCode} does not exist.`);
            return;
        }

        console.log(`🗑️ (SERVER) ${playerName} discarded card: ${card}`);

        // Store discarded cards in the lobby state
        if (!lobbies[lobbyCode].discardedCards) {
            lobbies[lobbyCode].discardedCards = [];
        }
        lobbies[lobbyCode].discardedCards.push({ playerName, card });

        // Broadcast to all players about the discarded card
        io.to(lobbyCode).emit('card_discarded', {
            playerName,
            card,
        });

        // Trigger reverse scale animation for all clients if required
        if (animateReverse) {
            io.to(lobbyCode).emit('reset_deck_scale', {
                playerName: playerName
            });
        }

        // Check if the card is a face card with special ability:
        if (card.startsWith('J')) {
            // Activate Jack ability
            lobbies[lobbyCode].jackAbilityActive = true;
            io.to(lobbies[lobbyCode].players.find(p => p.name === playerName).id)
                .emit('jack_ability_active', { message: 'Select a card to reveal as your power.' });
            return;
        } else if (card.startsWith('Q')) {
            // Activate Queen ability: player must select two cards to swap
            lobbies[lobbyCode].queenAbilityActive = true;
            // Initialize an empty array to store the two selections
            lobbies[lobbyCode].queenSelections = [];
            io.to(lobbies[lobbyCode].players.find(p => p.name === playerName).id)
                .emit('queen_ability_active', { message: 'Select 2 cards to swap.' });
            // Do not advance the turn until the Queen ability is resolved
            return;
        }

        // If not a face card with special ability, move to next turn immediately:
        const lobby = lobbies[lobbyCode];
        const turnOrder = lobby.turnOrder || [];
        if (turnOrder.length === 0) {
            console.log(`⚠️ (SERVER) No turn order found for lobby ${lobbyCode}`);
            return;
        }
        if (typeof lobby.turnIndex !== 'number') lobby.turnIndex = 0;
        lobby.turnIndex = (lobby.turnIndex + 1) % turnOrder.length;
        const nextPlayer = turnOrder[lobby.turnIndex];

        console.log(`➡️ (SERVER) Next turn: ${nextPlayer}`);
        io.to(lobbyCode).emit('next_turn', {
            currentPlayer: nextPlayer,
            nextPlayer: turnOrder[(lobby.turnIndex + 1) % turnOrder.length],
        });
    });

    // Handle Queen card selections (similar to the Jack selection):
    socket.on('queen_card_selected', (data) => {
        const { lobbyCode, owner, cardIndex, selectingPlayer } = data;
        const lobby = lobbies[lobbyCode];
        if (!lobby) {
            console.log(`❌ Lobby ${lobbyCode} does not exist.`);
            return;
        }

        // Ensure the Queen ability is active
        if (!lobby.queenAbilityActive) {
            console.log(`⚠️ (SERVER) Queen ability not active for lobby ${lobbyCode}`);
            return;
        }

        // Initialize the queenSelections array if it doesn't exist
        if (!lobby.queenSelections) {
            lobby.queenSelections = [];
        }

        // Prevent selecting more than 2 cards
        if (lobby.queenSelections.length >= 2) {
            console.log(`⚠️ (SERVER) Already received 2 selections for Queen ability in lobby ${lobbyCode}`);
            return;
        }

        lobby.queenSelections.push({ owner, cardIndex, selectingPlayer });
        console.log(`👑 (SERVER) Queen card selected: cardIndex ${cardIndex} from ${owner} by ${selectingPlayer}`);

        // Broadcast the selection to all clients (so they can highlight the card)
        io.to(lobbyCode).emit('queen_card_selected', { owner, cardIndex, selectingPlayer });

        // Once two selections have been made, trigger the swap animation
        if (lobby.queenSelections.length === 2) {
            // Broadcast the swap details so all clients can animate the swap
            io.to(lobbyCode).emit('queen_swap', { selections: lobby.queenSelections });
            logCurrentHands(lobbyCode);

            // Reset Queen ability state
            lobby.queenAbilityActive = false;
            lobby.queenSelections = [];

            // Optionally delay advancing the turn to let swap animations complete
            setTimeout(() => {
                const turnOrder = lobby.turnOrder || [];
                if (turnOrder.length === 0) {
                    console.log(`⚠️ (SERVER) No turn order found for lobby ${lobbyCode}`);
                    return;
                }
                if (typeof lobby.turnIndex !== 'number') lobby.turnIndex = 0;
                lobby.turnIndex = (lobby.turnIndex + 1) % turnOrder.length;
                const nextPlayer = turnOrder[lobby.turnIndex];

                console.log(`➡️ (SERVER) Next turn after Queen ability: ${nextPlayer}`);
                io.to(lobbyCode).emit('next_turn', {
                    currentPlayer: nextPlayer,
                    nextPlayer: turnOrder[(lobby.turnIndex + 1) % turnOrder.length],
                });
            }, 1200); // Delay to allow swap animation to complete (adjust as needed)
        }
    });

    socket.on('jack_ability_complete', (data) => {
        const { lobbyCode, playerName } = data;
        const lobby = lobbies[lobbyCode];
        if (!lobby) {
            console.log(`❌ Lobby ${lobbyCode} does not exist.`);
            return;
        }

        // Ensure the jack ability is active before proceeding
        if (!lobby.jackAbilityActive) {
            console.log(`⚠️ (SERVER) Jack ability not active for lobby ${lobbyCode}`);
            return;
        }

        // Reset the jack ability flag
        lobby.jackAbilityActive = false;

        // Now, move to the next turn as normal:
        const turnOrder = lobby.turnOrder || [];
        if (turnOrder.length === 0) {
            console.log(`⚠️ (SERVER) No turn order found for lobby ${lobbyCode}`);
            return;
        }
        if (typeof lobby.turnIndex !== 'number') lobby.turnIndex = 0;
        lobby.turnIndex = (lobby.turnIndex + 1) % turnOrder.length;
        const nextPlayer = turnOrder[lobby.turnIndex];

        console.log(`➡️ (SERVER) Next turn after Jack ability: ${nextPlayer}`);
        io.to(lobbyCode).emit('next_turn', {
            currentPlayer: nextPlayer,
            nextPlayer: turnOrder[(lobby.turnIndex + 1) % turnOrder.length],
        });
    });

    socket.on('reset_deck_scale', (data) => {
        const lobbyCode = data.lobbyCode;
        const playerName = data.playerName; // Extract player name from incoming data

        // ✅ Emit the reset_deck_scale event with playerName in payload
        io.to(lobbyCode).emit('reset_deck_scale', {
            playerName: playerName
        });
    });

    socket.on('reverse_animation_complete', (data) => {
        const { lobbyCode, playerName } = data;

        if (!lobbies[lobbyCode]) {
            console.log(`❌ Lobby ${lobbyCode} does not exist.`);
            return;
        }

        console.log(`✅ (SERVER) Reverse animation complete for ${playerName}`);

        // 🔥 Move to the next turn
        const lobby = lobbies[lobbyCode];
        const turnOrder = lobby.turnOrder || [];

        if (turnOrder.length === 0) {
            console.log(`⚠️ (SERVER) No turn order found for lobby ${lobbyCode}`);
            return;
        }

        // Initialize turnIndex if missing
        if (typeof lobby.turnIndex !== 'number') lobby.turnIndex = 0;

        // Increment turn index and wrap around
        lobby.turnIndex = (lobby.turnIndex + 1) % turnOrder.length;
        const nextPlayer = turnOrder[lobby.turnIndex];

        console.log(`➡️ (SERVER) Next turn: ${nextPlayer}`);

        // Emit the next_turn event to all players
        io.to(lobbyCode).emit('next_turn', {
            currentPlayer: nextPlayer,
            nextPlayer: turnOrder[(lobby.turnIndex + 1) % turnOrder.length],
        });
    });

    socket.on('skip_turn', (data) => {
        const { lobbyCode, playerName } = data;

        if (!lobbies[lobbyCode]) {
            console.log(`❌ Lobby ${lobbyCode} does not exist.`);
            return;
        }

        const lobby = lobbies[lobbyCode];
        const turnOrder = lobby.turnOrder || [];

        if (turnOrder.length === 0) {
            console.log(`⚠️ (SERVER) No turn order found for lobby ${lobbyCode}`);
            return;
        }

        // Ensure turnIndex is set
        if (typeof lobby.turnIndex !== 'number') lobby.turnIndex = 0;

        console.log(`🚫 (SERVER) ${playerName} skipped their turn.`);

        // Move to the next player
        lobby.turnIndex = (lobby.turnIndex + 1) % turnOrder.length;
        const nextPlayer = turnOrder[lobby.turnIndex];

        console.log(`➡️ (SERVER) Skipped. Next turn: ${nextPlayer}`);

        // Notify all players about the new turn
        io.to(lobbyCode).emit('next_turn', {
            currentPlayer: nextPlayer,
            nextPlayer: turnOrder[(lobby.turnIndex + 1) % turnOrder.length],
        });

        // Show log message on all clients
        io.to(lobbyCode).emit('show_log_message', {
            message: `${playerName} skipped their turn.`,
        });
    });

    socket.on('discard_pile_card_selected', (data) => {
        const { lobbyCode, card } = data;

        if (!lobbies[lobbyCode]) {
            console.log(`❌ Lobby ${lobbyCode} does not exist.`);
            return;
        }

        console.log(`🃏 (SERVER) Top discarded card selected: ${card}`);

        // Broadcast to all players that this card has been selected
        io.to(lobbyCode).emit('highlight_discarded_card', { card });
    });

    socket.on('reset_discarded_card', (data) => {
        const { lobbyCode } = data;

        if (!lobbies[lobbyCode]) {
            console.log(`❌ Lobby ${lobbyCode} does not exist.`);
            return;
        }

        console.log(`🔄 (SERVER) Resetting discarded card selection for all players in lobby ${lobbyCode}`);

        // Broadcast to all players to reset the discarded card selection
        io.to(lobbyCode).emit('reset_discarded_card');
    });

    socket.on('replace_card', (data) => {
        const { lobbyCode, playerName, replacedCard, newCard, replaceIndex, wasDrawnFromDeck } = data;
    
        if (!lobbies[lobbyCode]) {
            console.log(`❌ Lobby ${lobbyCode} does not exist.`);
            return;
        }
    
        console.log(`🔄 (SERVER) ${playerName} replaced ${replacedCard} with ${newCard} (From Deck: ${wasDrawnFromDeck})`);
    
        // ✅ Ensure `playerHands` exists
        if (!lobbies[lobbyCode].playerHands) {
            lobbies[lobbyCode].playerHands = {};
        }
    
        // ✅ Ensure player's hand exists
        if (!lobbies[lobbyCode].playerHands[playerName]) {
            lobbies[lobbyCode].playerHands[playerName] = [];
        }
    
        // ✅ Update the player's hand
        if (lobbies[lobbyCode].playerHands[playerName][replaceIndex] !== undefined) {
            lobbies[lobbyCode].playerHands[playerName][replaceIndex] = newCard;
        } else {
            console.log(`⚠️ (SERVER) Invalid replace index: ${replaceIndex} for ${playerName}`);
        }
    
        // ✅ Log updated hands
        logCurrentHands(lobbyCode);
    
        // Move to next turn
        const lobby = lobbies[lobbyCode];
        const turnOrder = lobby.turnOrder || [];
        lobby.turnIndex = (lobby.turnIndex + 1) % turnOrder.length;
        const nextPlayer = turnOrder[lobby.turnIndex];
    
        console.log(`➡️ (SERVER) Next turn: ${nextPlayer}`);
        io.to(lobbyCode).emit('next_turn', { currentPlayer: nextPlayer, nextPlayer: turnOrder[(lobby.turnIndex + 1) % turnOrder.length] });
    });
    

    socket.on('flip_card_back', (data) => {
        const { lobbyCode, playerName, replaceIndex, wasDrawnFromDeck } = data;

        io.to(lobbyCode).emit('flip_card_back', {
            playerName,
            replaceIndex,
            wasDrawnFromDeck, // ✅ Ensure this flag is sent to clients
        });
    });


    socket.on('jack_card_selected', (data) => {
        const { lobbyCode, owner, cardIndex, selectingPlayer } = data;
        // Broadcast to all clients in the lobby
        io.to(lobbyCode).emit('jack_card_selected', { owner, cardIndex, selectingPlayer });
    });

    socket.on('queen_card_unselected', (data) => {
        const { lobbyCode, owner, cardIndex, selectingPlayer } = data;
        const lobby = lobbies[lobbyCode];
        if (!lobby) {
            console.log(`❌ Lobby ${lobbyCode} does not exist.`);
            return;
        }
        // Remove this selection from the server's queenSelections array, if present.
        if (lobby.queenSelections) {
            lobby.queenSelections = lobby.queenSelections.filter(
                sel => !(sel.owner === owner && sel.cardIndex === cardIndex)
            );
        }
        // Broadcast the unselection event so that all clients can update their UI.
        io.to(lobbyCode).emit('queen_card_unselected', { owner, cardIndex, selectingPlayer });
    });


});

function logCurrentHands(lobbyCode) {
    if (!lobbies[lobbyCode]) return;

    let handsLog = "{\n";

    lobbies[lobbyCode].players.forEach((player, index) => {
        const playerName = player.name;
        const hand = lobbies[lobbyCode].playerHands[playerName] || [];

        // Convert hand into the correct format
        const formattedHand = hand.map(card => `'${card}'`).join(', ');

        // Append to handsLog
        handsLog += `  ${playerName}: [ ${formattedHand} ]`;

        // Add comma for all except the last player
        if (index < lobbies[lobbyCode].players.length - 1) {
            handsLog += ",";
        }
        handsLog += "\n";
    });

    handsLog += "}";

    console.log(`🃏 Hands summary: ${handsLog}`);
}


// Create a standard 52-card deck
const createDeck = () => {
    const suits = ['♠', '♥', '♦', '♣'];
    const values = ['2', '3', 'J', 'J', 'J', 'J', 'J', 'Q', 'Q', 'J', 'Q', 'K', 'A'];
    const deck = [];

    suits.forEach(suit => {
        values.forEach(value => {
            deck.push(`${value}${suit}`);
        });
    });

    return deck;
};

// Shuffle the deck using Fisher-Yates algorithm
const shuffleDeck = (deck) => {
    for (let i = deck.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [deck[i], deck[j]] = [deck[j], deck[i]];
    }
    return deck;
};



server.listen(3000, () => {
    console.log('Server running on http://localhost:3000');
});
