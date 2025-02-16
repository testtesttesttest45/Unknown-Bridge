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

io.on('connection', (socket) => {
    console.log(`A user connected: ${socket.id}`);

    // Handle "create_party" request
    socket.on('create_party', () => {
        // Generate a unique 4-digit lobby code
        let lobbyCode;
        do {
            lobbyCode = Math.floor(1000 + Math.random() * 9000).toString();
        } while (lobbies[lobbyCode]); // Ensure uniqueness

        // Store lobby with the host player
        lobbies[lobbyCode] = {
            host: socket.id,
            players: [socket.id],
        };

        console.log(`Lobby created: ${lobbyCode} by ${socket.id}`);

        // Send the generated lobby code back to the client
        socket.emit('party_created', { lobbyCode });
    });

    // Handle disconnect
    socket.on('disconnect', () => {
        console.log(`A user disconnected: ${socket.id}`);

        // Remove player from any lobbies
        for (const [code, lobby] of Object.entries(lobbies)) {
            if (lobby.players.includes(socket.id)) {
                lobby.players = lobby.players.filter(id => id !== socket.id);

                // If lobby is empty, delete it
                if (lobby.players.length === 0) {
                    delete lobbies[code];
                    console.log(`Lobby ${code} deleted.`);
                }
            }
        }
    });
});

server.listen(3000, () => {
    console.log('Server running on http://localhost:3000');
});
