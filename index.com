<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Legend of Eldoria - Free Movement RPG</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
            user-select: none;
        }
        body, html {
            width: 100%;
            height: 100%;
            overflow: hidden;
            background-color: #050505;
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        }
        #game-container {
            position: relative;
            width: 100vw;
            height: 100vh;
        }
        canvas {
            display: block;
            background: #111;
        }
        /* UI HUD */
        #hud {
            position: absolute;
            top: 15px;
            left: 15px;
            color: #fff;
            pointer-events: none;
            display: flex;
            flex-direction: column;
            gap: 8px;
            z-index: 10;
        }
        .bar-container {
            width: 220px;
            height: 18px;
            background: rgba(0, 0, 0, 0.6);
            border: 2px solid #555;
            border-radius: 9px;
            overflow: hidden;
            position: relative;
        }
        .bar-fill {
            height: 100%;
            width: 100%;
            transition: width 0.1s linear;
        }
        #hp-fill { background: linear-gradient(90deg, #e74c3c, #c0392b); }
        #mp-fill { background: linear-gradient(90deg, #3498db, #2980b9); }
        .bar-text {
            position: absolute;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            font-size: 11px;
            font-weight: bold;
            text-shadow: 1px 1px 2px #000;
        }
        #stats-info {
            font-size: 14px;
            font-weight: bold;
            color: #f1c40f;
            text-shadow: 1px 1px 2px #000;
        }
        /* Controls & Action Overlay */
        #action-ui {
            position: absolute;
            bottom: 20px;
            right: 20px;
            display: flex;
            gap: 10px;
            z-index: 10;
        }
        .btn-action {
            padding: 12px 18px;
            background: #27ae60;
            color: #fff;
            border: 2px solid #2ecc71;
            border-radius: 8px;
            font-weight: bold;
            cursor: pointer;
            box-shadow: 0 4px 6px rgba(0,0,0,0.4);
            transition: transform 0.1s, background 0.2s;
        }
        .btn-action:hover {
            background: #2ecc71;
            transform: translateY(-2px);
        }
        .btn-action:active {
            transform: translateY(0);
        }
        /* Notification Toast */
        #notification {
            position: absolute;
            top: 20px;
            left: 50%;
            transform: translateX(-50%);
            background: rgba(0,0,0,0.8);
            color: #f39c12;
            padding: 10px 20px;
            border: 1px solid #f1c40f;
            border-radius: 6px;
            font-weight: bold;
            display: none;
            z-index: 20;
        }
        /* Quiz Modal Popup */
        #quiz-modal {
            position: absolute;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            background: rgba(20, 20, 30, 0.95);
            border: 3px solid #f1c40f;
            border-radius: 12px;
            padding: 25px;
            width: 420px;
            color: #fff;
            display: none;
            flex-direction: column;
            gap: 15px;
            box-shadow: 0 0 20px rgba(241, 196, 15, 0.4);
            z-index: 30;
        }
        #quiz-modal h3 {
            color: #f1c40f;
            text-align: center;
        }
        .quiz-opt {
            padding: 10px;
            background: #2c3e50;
            border: 1px solid #34495e;
            border-radius: 6px;
            color: #fff;
            cursor: pointer;
            text-align: left;
            transition: background 0.2s;
        }
        .quiz-opt:hover {
            background: #34495e;
        }
    </style>
</head>
<body>
    <div id="game-container">
        <canvas id="gameCanvas"></canvas>
        
        <!-- HUD Player -->
        <div id="hud">
            <div id="stats-info">Lv. 1 Adventurer | EXP: 0/100</div>
            <div class="bar-container">
                <div id="hp-fill" class="bar-fill"></div>
                <div class="bar-text" id="hp-text">HP: 100 / 100</div>
            </div>
            <div class="bar-container">
                <div id="mp-fill" class="bar-fill"></div>
                <div class="bar-text" id="mp-text">MP: 50 / 50</div>
            </div>
            <div style="font-size:12px; color:#aaa; margin-top:5px;">
                WASD: Move | Click: Attack | Q,E: Skill | Space: Dash
            </div>
        </div>

        <!-- Action Button UI -->
        <div id="action-ui">
            <button class="btn-action" onclick="recruitSoldier()">Rekrut Prajurit (Max 5)</button>
            <button class="btn-action" style="background:#8e44ad; border-color:#9b59b6;" onclick="spawnMedkit()">Drop HP Box</button>
        </div>

        <!-- Notification -->
        <div id="notification"></div>

        <!-- Quiz Modal (Chest Security System) -->
        <div id="quiz-modal">
            <h3>CYBER SECURITY CHEST</h3>
            <p id="quiz-question">Pertanyaan quiz PC...</p>
            <button class="quiz-opt" onclick="answerQuiz(0)" id="opt0"></button>
            <button class="quiz-opt" onclick="answerQuiz(1)" id="opt1"></button>
            <button class="quiz-opt" onclick="answerQuiz(2)" id="opt2"></button>
            <button class="quiz-opt" onclick="answerQuiz(3)" id="opt3"></button>
        </div>
    </div>

    <script>
        const canvas = document.getElementById('gameCanvas');
        const ctx = canvas.getContext('2d');

        function resizeCanvas() {
            canvas.width = window.innerWidth;
            canvas.height = window.innerHeight;
        }
        window.addEventListener('resize', resizeCanvas);
        resizeCanvas();

        // System Audio Generator (Web Audio API)
        const audioCtx = new (window.AudioContext || window.webkitAudioContext)();
        function playSound(freq, duration, type = 'sine') {
            if (audioCtx.state === 'suspended') audioCtx.resume();
            const osc = audioCtx.createOscillator();
            const gain = audioCtx.createGain();
            osc.type = type;
            osc.frequency.setValueAtTime(freq, audioCtx.currentTime);
            gain.gain.setValueAtTime(0.1, audioCtx.currentTime);
            gain.gain.exponentialRampToValueAtTime(0.01, audioCtx.currentTime + duration);
            osc.connect(gain);
            gain.connect(audioCtx.destination);
            osc.start();
            osc.stop(audioCtx.currentTime + duration);
        }

        // Global State & Inputs
        const keys = {};
        const mouse = { x: 0, y: 0 };
        const WORLD_SIZE = 3000;

        window.addEventListener('keydown', e => keys[e.key.toLowerCase()] = true);
        window.addEventListener('keyup', e => keys[e.key.toLowerCase()] = false);
        window.addEventListener('mousemove', e => {
            mouse.x = e.clientX;
            mouse.y = e.clientY;
        });

        // Camera System
        const camera = { x: 0, y: 0 };

        // Player Entity
        const player = {
            x: 1500,
            y: 1500,
            radius: 16,
            speed: 4.5,
            hp: 100,
            maxHp: 100,
            mp: 50,
            maxMp: 50,
            level: 1,
            exp: 0,
            nextExp: 100,
            angle: 0,
            dashCd: 0,
            isDashing: false,
            dashTimer: 0,
            attackCd: 0,
            qCd: 0,
            eCd: 0
        };

        // Class HP Box (Medkit)
        class HPBox {
            constructor(x, y) {
                this.x = x;
                this.y = y;
                this.radius = 12;
                this.healAmount = 40;
                this.collected = false;
            }
            draw(ctx, camera) {
                if (this.collected) return;
                const sx = this.x - camera.x;
                const sy = this.y - camera.y;

                ctx.fillStyle = '#e74c3c';
                ctx.fillRect(sx - 10, sy - 10, 20, 20);
                ctx.strokeStyle = '#ffffff';
                ctx.lineWidth = 2;
                ctx.strokeRect(sx - 10, sy - 10, 20, 20);

                ctx.fillStyle = '#ffffff';
                ctx.fillRect(sx - 6, sy - 2, 12, 4);
                ctx.fillRect(sx - 2, sy - 6, 4, 12);
            }
        }

        // Class Prajurit Ally (Max 5)
        class AllySoldier {
            constructor(x, y) {
                this.x = x;
                this.y = y;
                this.radius = 14;
                this.speed = 3.8;
                this.hp = 120;
                this.maxHp = 120;
                this.damage = 15;
                this.attackRange = 35;
                this.attackCd = 0;
            }
            update(enemies) {
                let nearest = null;
                let minDist = 250;

                enemies.forEach(enemy => {
                    const dist = Math.hypot(enemy.x - this.x, enemy.y - this.y);
                    if (dist < minDist) {
                        minDist = dist;
                        nearest = enemy;
                    }
                });

                if (nearest) {
                    const angle = Math.atan2(nearest.y - this.y, nearest.x - this.x);
                    if (minDist > this.attackRange) {
                        this.x += Math.cos(angle) * this.speed;
                        this.y += Math.sin(angle) * this.speed;
                    } else if (this.attackCd <= 0) {
                        nearest.hp -= this.damage;
                        playSound(300, 0.1, 'square');
                        createParticles(nearest.x, nearest.y, '#e67e22', 4);
                        this.attackCd = 35;
                    }
                } else {
                    const distToPlayer = Math.hypot(player.x - this.x, player.y - this.y);
                    if (distToPlayer > 50) {
                        const angle = Math.atan2(player.y - this.y, player.x - this.x);
                        this.x += Math.cos(angle) * this.speed;
                        this.y += Math.sin(angle) * this.speed;
                    }
                }
                if (this.attackCd > 0) this.attackCd--;
            }
            draw(ctx, camera) {
                const sx = this.x - camera.x;
                const sy = this.y - camera.y;

                ctx.beginPath();
                ctx.arc(sx, sy, this.radius, 0, Math.PI * 2);
                ctx.fillStyle = '#3498db';
                ctx.fill();
                ctx.strokeStyle = '#2980b9';
                ctx.lineWidth = 2;
                ctx.stroke();

                ctx.fillStyle = '#c0392b';
                ctx.fillRect(sx - 12, sy - 18, 24, 3);
                ctx.fillStyle = '#2ecc71';
                ctx.fillRect(sx - 12, sy - 18, (this.hp / this.maxHp) * 24, 3);
            }
        }

        // Class Enemy (15 Tipe Base)
        class Enemy {
            constructor(x, y, type) {
                this.x = x;
                this.y = y;
                this.type = type;
                this.radius = 15;
                this.speed = 2 + Math.random() * 1.5;
                this.hp = 50 + type * 20;
                this.maxHp = this.hp;
                this.damage = 8 + type * 2;
                this.color = `hsl(${type * 24}, 70%, 50%)`;
            }
            update() {
                const dist = Math.hypot(player.x - this.x, player.y - this.y);
                if (dist < 400) {
                    const angle = Math.atan2(player.y - this.y, player.x - this.x);
                    this.x += Math.cos(angle) * this.speed;
                    this.y += Math.sin(angle) * this.speed;

                    if (dist < player.radius + this.radius) {
                        player.hp = Math.max(0, player.hp - 0.2);
                    }
                }
            }
            draw(ctx, camera) {
                const sx = this.x - camera.x;
                const sy = this.y - camera.y;

                ctx.beginPath();
                ctx.arc(sx, sy, this.radius, 0, Math.PI * 2);
                ctx.fillStyle = this.color;
                ctx.fill();
                ctx.strokeStyle = '#000';
                ctx.lineWidth = 2;
                ctx.stroke();
            }
        }

        // Particle System
        const particles = [];
        function createParticles(x, y, color, count = 8) {
            for (let i = 0; i < count; i++) {
                particles.push({
                    x, y,
                    vx: (Math.random() - 0.5) * 6,
                    vy: (Math.random() - 0.5) * 6,
                    life: 20,
                    color
                });
            }
        }

        // Lists & Collections
        const hpBoxes = [new HPBox(1400, 1400), new HPBox(1600, 1600)];
        const allies = [];
        const enemies = [];
        const maxAllies = 5;

        // Spawn Initial Enemies
        for (let i = 0; i < 30; i++) {
            enemies.push(new Enemy(
                Math.random() * WORLD_SIZE,
                Math.random() * WORLD_SIZE,
                Math.floor(Math.random() * 15)
            ));
        }

        // Action Trigger Functions
        function showNotification(text) {
            const el = document.getElementById('notification');
            el.innerText = text;
            el.style.display = 'block';
            setTimeout(() => el.style.display = 'none', 2500);
        }

        function recruitSoldier() {
            if (allies.length < maxAllies) {
                allies.push(new AllySoldier(player.x + Math.random() * 40, player.y + Math.random() * 40));
                showNotification(`Prajurit Direkrut! (${allies.length}/${maxAllies})`);
                playSound(600, 0.15, 'triangle');
            } else {
                showNotification(`Batas Maksimum Prajurit (5/5)!`);
            }
        }

        function spawnMedkit() {
            hpBoxes.push(new HPBox(player.x + 50, player.y + 50));
            showNotification("HP Box dijatuhkan!");
        }

        // Player Controls & Combat Inputs
        window.addEventListener('mousedown', e => {
            if (e.button === 0 && player.attackCd <= 0) { // Left Click Attack
                player.attackCd = 15;
                playSound(400, 0.08, 'sawtooth');
                enemies.forEach(enemy => {
                    const dist = Math.hypot(enemy.x - player.x, enemy.y - player.y);
                    if (dist < 70) {
                        enemy.hp -= 25;
                        createParticles(enemy.x, enemy.y, '#f1c40f', 6);
                    }
                });
            }
        });

        // Main Movement & Update Loop
        function update() {
            // Player Movement (WASD Free 360 Vector)
            let dx = 0;
            let dy = 0;
            if (keys['w']) dy -= 1;
            if (keys['s']) dy += 1;
            if (keys['a']) dx -= 1;
            if (keys['d']) dx += 1;

            if (dx !== 0 && dy !== 0) {
                dx *= 0.7071;
                dy *= 0.7071;
            }

            let moveSpeed = player.speed;
            if (keys[' '] && player.dashCd <= 0) { // Space Dash
                player.isDashing = true;
                player.dashTimer = 8;
                player.dashCd = 45;
                playSound(800, 0.1, 'square');
            }

            if (player.dashTimer > 0) {
                moveSpeed *= 2.5;
                player.dashTimer--;
            }
            if (player.dashCd > 0) player.dashCd--;
            if (player.attackCd > 0) player.attackCd--;

            player.x = Math.max(20, Math.min(WORLD_SIZE - 20, player.x + dx * moveSpeed));
            player.y = Math.max(20, Math.min(WORLD_SIZE - 20, player.y + dy * moveSpeed));

            // Camera Tracking Player
            camera.x = player.x - canvas.width / 2;
            camera.y = player.y - canvas.height / 2;

            // HP Box Interaction
            hpBoxes.forEach(box => {
                if (!box.collected) {
                    const dist = Math.hypot(player.x - box.x, player.y - box.y);
                    if (dist < player.radius + box.radius) {
                        box.collected = true;
                        player.hp = Math.min(player.maxHp, player.hp + box.healAmount);
                        createParticles(player.x, player.y, '#2ecc71', 10);
                        playSound(523, 0.2, 'sine');
                        showNotification("+40 HP Dipulihkan!");
                    }
                }
            });

            // Allies Update
            for (let i = allies.length - 1; i >= 0; i--) {
                const ally = allies[i];
                ally.update(enemies);
                if (ally.hp <= 0) allies.splice(i, 1);
            }

            // Enemies Update
            for (let i = enemies.length - 1; i >= 0; i--) {
                const enemy = enemies[i];
                enemy.update();
                if (enemy.hp <= 0) {
                    enemies.splice(i, 1);
                    player.exp += 20;
                    if (player.exp >= player.nextExp) {
                        player.level++;
                        player.exp = 0;
                        player.maxHp += 20;
                        player.hp = player.maxHp;
                        showNotification(`LEVEL UP! Sekarang Level ${player.level}`);
                        playSound(880, 0.3, 'sine');
                    }
                }
            }

            // Particles Update
            for (let i = particles.length - 1; i >= 0; i--) {
                const p = particles[i];
                p.x += p.vx;
                p.y += p.vy;
                p.life--;
                if (p.life <= 0) particles.splice(i, 1);
            }

            // Update UI HUD
            document.getElementById('hp-fill').style.width = (player.hp / player.maxHp * 100) + '%';
            document.getElementById('hp-text').innerText = `HP: ${Math.ceil(player.hp)} / ${player.maxHp}`;
            document.getElementById('mp-fill').style.width = (player.mp / player.maxMp * 100) + '%';
            document.getElementById('stats-info').innerText = `Lv. ${player.level} Adventurer | EXP: ${player.exp}/${player.nextExp}`;
        }

        // Render Loop
        function render() {
            ctx.clearRect(0, 0, canvas.width, canvas.height);

            // Render Grid / Map Boundaries
            ctx.strokeStyle = '#222';
            ctx.lineWidth = 1;
            const gridSize = 100;
            const startX = -camera.x % gridSize;
            const startY = -camera.y % gridSize;

            for (let x = startX; x < canvas.width; x += gridSize) {
                ctx.beginPath();
                ctx.moveTo(x, 0);
                ctx.lineTo(x, canvas.height);
                ctx.stroke();
            }
            for (let y = startY; y < canvas.height; y += gridSize) {
                ctx.beginPath();
                ctx.moveTo(0, y);
                ctx.lineTo(canvas.width, y);
                ctx.stroke();
            }

            // Render Entities
            hpBoxes.forEach(box => box.draw(ctx, camera));
            allies.forEach(ally => ally.draw(ctx, camera));
            enemies.forEach(enemy => enemy.draw(ctx, camera));

            // Render Particles
            particles.forEach(p => {
                ctx.fillStyle = p.color;
                ctx.fillRect(p.x - camera.x, p.y - camera.y, 4, 4);
            });

            // Render Player
            const px = player.x - camera.x;
            const py = player.y - camera.y;

            ctx.beginPath();
            ctx.arc(px, py, player.radius, 0, Math.PI * 2);
            ctx.fillStyle = '#f1c40f';
            ctx.fill();
            ctx.strokeStyle = '#fff';
            ctx.lineWidth = 2;
            ctx.stroke();
        }

        function gameLoop() {
            update();
            render();
            requestAnimationFrame(gameLoop);
        }

        gameLoop();
    </script>
</body>
</html>
