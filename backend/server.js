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
    




});


server.listen(3000, () => {
    console.log('Server running on http://localhost:3000');
});
