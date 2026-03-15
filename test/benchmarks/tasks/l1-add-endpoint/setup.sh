#!/bin/bash
# Setup baseline Express + TypeScript project for L1 benchmark
set -e

TASK_DIR="$1"
cd "$TASK_DIR"

# Initialize project
cat > package.json << 'EOF'
{
  "name": "benchmark-api",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "tsx watch src/index.ts",
    "build": "tsc",
    "start": "node dist/index.js",
    "test": "vitest run"
  },
  "dependencies": {
    "express": "^4.18.2"
  },
  "devDependencies": {
    "@types/express": "^4.17.21",
    "@types/node": "^20.10.0",
    "tsx": "^4.7.0",
    "typescript": "^5.3.0",
    "vitest": "^1.2.0",
    "supertest": "^6.3.0",
    "@types/supertest": "^6.0.0"
  }
}
EOF

cat > tsconfig.json << 'EOF'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "node",
    "esModuleInterop": true,
    "strict": true,
    "outDir": "dist",
    "rootDir": "src"
  },
  "include": ["src"]
}
EOF

mkdir -p src/routes

cat > src/index.ts << 'EOF'
import express from 'express';
import { usersRouter } from './routes/users.js';

const app = express();
app.use(express.json());

app.use('/users', usersRouter);

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});

export { app };
EOF

cat > src/routes/users.ts << 'EOF'
import { Router } from 'express';

export const usersRouter = Router();

usersRouter.get('/', (req, res) => {
  res.json([{ id: 1, name: 'Test User' }]);
});
EOF

cat > src/db.ts << 'EOF'
// Simulated database connection
let connected = false;

export async function connectDb(): Promise<void> {
  await new Promise(resolve => setTimeout(resolve, 100));
  connected = true;
}

export async function pingDb(): Promise<number> {
  const start = Date.now();
  await new Promise(resolve => setTimeout(resolve, 10));
  return Date.now() - start;
}

export function isConnected(): boolean {
  return connected;
}
EOF

mkdir -p test

cat > test/users.test.ts << 'EOF'
import { describe, it, expect } from 'vitest';
import request from 'supertest';
import { app } from '../src/index.js';

describe('GET /users', () => {
  it('returns user list', async () => {
    const res = await request(app).get('/users');
    expect(res.status).toBe(200);
    expect(res.body).toHaveLength(1);
  });
});
EOF

cat > vitest.config.ts << 'EOF'
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
  },
});
EOF

# Install dependencies
npm install --silent

# Initialize git
git init -q
git add .
git commit -q -m "Initial baseline project"

echo "Setup complete: Express + TypeScript baseline project"
