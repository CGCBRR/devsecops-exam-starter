# ============================================
# Stage 1: Build stage — install all deps
# ============================================
FROM node:20-alpine AS builder

WORKDIR /app

# Copy package files first for better layer caching
COPY package*.json ./

# Reproducible install from package-lock.json
RUN npm ci

# Copy app source
COPY server.js ./
COPY server.test.js ./

# ============================================
# Stage 2: Production stage — minimal & secure
# ============================================
FROM node:20-alpine AS production

WORKDIR /app

ENV NODE_ENV=production

# Install ONLY production dependencies (no jest, no supertest)
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Copy the app code from the builder stage, owned by 'node'
COPY --from=builder --chown=node:node /app/server.js ./

# Run as the built-in non-root 'node' user
USER node

EXPOSE 3000

CMD ["node", "server.js"]