# -----------------------------
# Build Stage
# -----------------------------
FROM node:16-alpine AS build

WORKDIR /app

# Install dependencies first (cache-friendly)
COPY package.json package-lock.json ./
RUN npm ci

# Copy source and build React app
COPY . .
RUN npm run build


# -----------------------------
# Runtime Stage
# -----------------------------
FROM node:16-alpine

WORKDIR /app

# Copy only required runtime artifacts
COPY --from=build /app/build ./build
COPY --from=build /app/server.js ./server.js
COPY --from=build /app/package.json ./package.json
COPY --from=build /app/package-lock.json ./package-lock.json

# Install only production dependencies
RUN npm ci --omit=dev

# Create non-root user (security hardening)
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

# Expose UI port
EXPOSE 3000

# Start Node server
CMD ["node", "server.js"]
