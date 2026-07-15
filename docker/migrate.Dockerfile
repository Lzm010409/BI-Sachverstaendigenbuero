# Schlankes Node-Image für den Migrations-Runner (und später ETL-Jobs).
FROM node:20-alpine

WORKDIR /app

# Nur Manifeste zuerst -> Layer-Caching.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY tsconfig.json ./
COPY sql ./sql
COPY scripts ./scripts
COPY etl ./etl
COPY fixtures ./fixtures

# Migrations-Lauf; exit 0 bei Erfolg, sonst != 0 (Deploy schlägt fehl).
CMD ["npx", "tsx", "scripts/migrate.ts"]
