FROM node:20-alpine

ENV NODE_ENV=production

WORKDIR /app

# Dépendances (package-lock.json requis pour reproductibilité)
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# Code source
COPY src ./src

EXPOSE 3000

# Migrations idempotentes au démarrage, puis serveur.
CMD ["sh", "-c", "node src/database/migrate.js && node src/server.js"]
