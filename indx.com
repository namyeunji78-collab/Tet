<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>Mobile Tetris Single File</title>
    <style>
        /* CSS 스타일 시작 */
        body {
            background: #202028;
            color: #fff;
            font-family: 'Malgun Gothic', sans-serif;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            height: 100vh;
            margin: 0;
            overflow: hidden;
            touch-action: none; /* 브라우저 기본 터치 동작 방지 */
        }

        .game-container {
            display: flex;
            flex-direction: column;
            align-items: center;
        }

        #score {
            font-size: 2rem;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.5);
        }

        canvas {
            border: 4px solid #fff;
            background-color: #000;
            box-shadow: 0 0 20px rgba(0,0,0,0.5);
            height: 50vh; /* 모바일 화면 크기 대응 */
        }

        .controls {
            margin-top: 20px;
            display: grid;
            grid-template-areas: 
                ". up ."
                "left down right";
            gap: 10px;
        }

        .btn {
            width: 70px;
            height: 70px;
            background: rgba(255, 255, 255, 0.2);
            border: 2px solid #fff;
            border-radius: 15px;
            color: white;
            font-size: 20px;
            font-weight: bold;
            display: flex;
            align-items: center;
            justify-content: center;
            user-select: none;
            -webkit-tap-highlight-color: transparent;
        }

        .btn:active {
            background: rgba(255, 255, 255, 0.5);
            transform: scale(0.95);
        }

        #rotate { grid-area: up; background: rgba(255, 165, 0, 0.4); }
        #left { grid-area: left; }
        #down { grid-area: down; }
        #right { grid-area: right; }
    </style>
</head>
<body>

    <div class="game-container">
        <div id="score">Score: 0</div>
        <canvas id="tetris" width="240" height="400"></canvas>
        
        <div class="controls">
            <div class="btn" id="rotate">회전</div>
            <div class="btn" id="left">◀</div>
            <div class="btn" id="down">▼</div>
            <div class="btn" id="right">▶</div>
        </div>
    </div>

    <script>
        /* JavaScript 로직 시작 */
        const canvas = document.getElementById('tetris');
        const context = canvas.getContext('2d');
        const scoreElement = document.getElementById('score');

        context.scale(20, 20);

        // 한 줄이 꽉 찼는지 확인 및 제거
        function arenaSweep() {
            let rowCount = 1;
            outer: for (let y = arena.length - 1; y > 0; --y) {
                for (let x = 0; x < arena[y].length; ++x) {
                    if (arena[y][x] === 0) continue outer;
                }
                const row = arena.splice(y, 1)[0].fill(0);
                arena.unshift(row);
                ++y;
                player.score += rowCount * 10;
                rowCount *= 2;
            }
            updateScore();
        }

        // 충돌 처리
        function collide(arena, player) {
            const [m, o] = [player.matrix, player.pos];
            for (let y = 0; y < m.length; ++y) {
                for (let x = 0; x < m[y].length; ++x) {
                    if (m[y][x] !== 0 && (arena[y + o.y] && arena[y + o.y][x + o.x]) !== 0) {
                        return true;
                    }
                }
            }
            return false;
        }

        // 게임 보드 생성
        function createMatrix(w, h) {
            const matrix = [];
            while (h--) matrix.push(new Array(w).fill(0));
            return matrix;
        }

        // 블록 생성
        function createPiece(type) {
            if (type === 'T') return [[0, 0, 0], [1, 1, 1], [0, 1, 0]];
            if (type === 'O') return [[2, 2], [2, 2]];
            if (type === 'L') return [[0, 3, 0], [0, 3, 0], [0, 3, 3]];
            if (type === 'J') return [[0, 4, 0], [0, 4, 0], [4, 4, 0]];
            if (type === 'I') return [[0, 5, 0, 0], [0, 5, 0, 0], [0, 5, 0, 0], [0, 5, 0, 0]];
            if (type === 'S') return [[0, 6, 6], [6, 6, 0], [0, 0, 0]];
            if (type === 'Z') return [[7, 7, 0], [0, 7, 7], [0, 0, 0]];
        }

        function draw() {
            context.fillStyle = '#000';
            context.fillRect(0, 0, canvas.width, canvas.height);
            drawMatrix(arena, {x: 0, y: 0});
            drawMatrix(player.matrix, player.pos);
        }

        function drawMatrix(matrix, offset) {
            const colors = [null, '#FF0D72', '#0DC2FF', '#0DFF72', '#F538FF', '#FF8E0D', '#FFE138', '#3877FF'];
            matrix.forEach((row, y) => {
                row.forEach((value, x) => {
                    if (value !== 0) {
                        context.fillStyle = colors[value];
                        context.fillRect(x + offset.x, y + offset.y, 1, 1);
                        // 테두리 효과
                        context.lineWidth = 0.05;
                        context.strokeStyle = 'white';
                        context.strokeRect(x + offset.x, y + offset.y, 1, 1);
                    }
                });
            });
        }

        function merge(arena, player) {
            player.matrix.forEach((row, y) => {
                row.forEach((value, x) => {
                    if (value !== 0) arena[y + player.pos.y][x + player.pos.x] = value;
                });
            });
        }

        function rotate(matrix, dir) {
            for (let y = 0; y < matrix.length; ++y) {
                for (let x = 0; x < y; ++x) {
                    [matrix[x][y], matrix[y][x]] = [matrix[y][x], matrix[x][y]];
                }
            }
            if (dir > 0) matrix.forEach(row => row.reverse());
            else matrix.reverse();
        }

        function playerDrop() {
            player.pos.y++;
            if (collide(arena, player)) {
                player.pos.y--;
                merge(arena, player);
                playerReset();
                arenaSweep();
            }
            dropCounter = 0;
        }

        function playerMove(dir) {
            player.pos.x += dir;
            if (collide(arena, player)) player.pos.x -= dir;
        }

        function playerRotate(dir) {
            const pos = player.pos.x;
            let offset = 1;
            rotate(player.matrix, dir);
            while (collide(arena, player)) {
                player.pos.x += offset;
                offset = -(offset + (offset > 0 ? 1 : -1));
                if (offset > player.matrix[0].length) {
                    rotate(player.matrix, -dir);
                    player.pos.x = pos;
                    return;
                }
            }
        }

        function playerReset() {
            const pieces = 'ILJOTSZ';
            player.matrix = createPiece(pieces[pieces.length * Math.random() | 0]);
            player.pos.y = 0;
            player.pos.x = (arena[0].length / 2 | 0) - (player.matrix[0].length / 2 | 0);
            if (collide(arena, player)) {
                arena.forEach(row => row.fill(0));
                player.score = 0;
                updateScore();
            }
        }

        function updateScore() {
            scoreElement.innerText = `Score: ${player.score}`;
        }

        let dropCounter = 0;
        let dropInterval = 1000;
        let lastTime = 0;

        function update(time = 0) {
            const deltaTime = time - lastTime;
            lastTime = time;
            dropCounter += deltaTime;
            if (dropCounter > dropInterval) playerDrop();
            draw();
            requestAnimationFrame(update);
        }

        const arena = createMatrix(12, 20);
        const player = { pos: {x: 0, y: 0}, matrix: null, score: 0 };

        // 버튼 이벤트 리스너 (터치/클릭 대응)
        document.getElementById('left').addEventListener('pointerdown', () => playerMove(-1));
        document.getElementById('right').addEventListener('pointerdown', () => playerMove(1));
        document.getElementById('down').addEventListener('pointerdown', () => playerDrop());
        document.getElementById('rotate').addEventListener('pointerdown', () => playerRotate(1));

        // 키보드 대응 (PC 테스트용)
        document.addEventListener('keydown', event => {
            if (event.keyCode === 37) playerMove(-1);
            else if (event.keyCode === 39) playerMove(1);
            else if (event.keyCode === 40) playerDrop();
            else if (event.keyCode === 81) playerRotate(-1);
            else if (event.keyCode === 87) playerRotate(1);
        });

        playerReset();
        updateScore();
        update();
    </script>
</body>
</html>
