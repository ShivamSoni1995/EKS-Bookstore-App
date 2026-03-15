# Build stage
FROM node:20-alpine AS build

WORKDIR /app

# Copy package files and install ALL dependencies (including devDependencies)
COPY package*.json ./
RUN npm ci --no-audit --no-fund

# Copy source code and build
COPY . .
RUN npm run build

# Production stage - use distroless for smallest size
FROM node:20-alpine AS production

WORKDIR /app

# Copy package files and install ONLY production dependencies
COPY package*.json ./
# Add npm retry settings for network resilience
ENV npm_config_fetch_retries=5
ENV npm_config_fetch_retry_factor=10
ENV npm_config_fetch_retry_mintimeout=20000
ENV npm_config_fetch_retry_maxtimeout=120000
# Use npm install instead of npm ci for better reliability
RUN npm install --only=production --no-audit --no-fund \
  && npm cache clean --force \
  && rm -rf /tmp/* /var/tmp/* \
  && rm -rf ~/.npm

# Copy built application from build stage
COPY --from=build /app/build ./build
COPY server.js .

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nextjs -u 1001 && \
    chown -R nextjs:nodejs /app

USER nextjs

EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/health', (res) => { process.exit(res.statusCode === 200 ? 0 : 1) })" || exit 1

CMD ["node", "server.js"]