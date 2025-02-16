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
        };

        console.log(`🎊 Lobby created: ${lobbyCode} by ${socket.id} (${playerName})`);
        console.log(`📢 Active lobbies: ${Object.keys(lobbies).length} (${Object.keys(lobbies).join(", ")})`);

        // Send the generated lobby code back to the client
        socket.emit('party_created', { lobbyCode });
    });


    socket.on('delete_party', (data) => {
        const { lobbyCode } = data;
        if (lobbies[lobbyCode]) {
            console.log(`🔥 Deleting lobby: ${lobbyCode}`);
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
});


server.listen(3000, () => {
    console.log('Server running on http://localhost:3000');
});
