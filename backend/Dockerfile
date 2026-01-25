# Stage 1: Build and Test
FROM node:21 AS backend-builder

# Setup the working directory
WORKDIR /app

# Copy package files for better layer caching
COPY package*.json ./

# Install all dependencies (including dev dependencies for tests)
RUN npm ci

# Copy source code
COPY . .

# Run tests
RUN npm run test

# Stage 2: Production
FROM node:21-slim

# Create a non-root user for security
RUN groupadd -r appuser && useradd -r -g appuser appuser

# Setup the working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install only production dependencies
RUN npm ci --only=production && npm cache clean --force

# Copy application code from builder stage (excluding node_modules)
COPY --from=backend-builder --chown=appuser:appuser /app/api ./api
COPY --from=backend-builder --chown=appuser:appuser /app/config ./config
COPY --from=backend-builder --chown=appuser:appuser /app/controllers ./controllers
COPY --from=backend-builder --chown=appuser:appuser /app/models ./models
COPY --from=backend-builder --chown=appuser:appuser /app/routes ./routes
COPY --from=backend-builder --chown=appuser:appuser /app/services ./services
COPY --from=backend-builder --chown=appuser:appuser /app/utils ./utils
COPY --from=backend-builder --chown=appuser:appuser /app/server.js ./
COPY --from=backend-builder --chown=appuser:appuser /app/.babelrc ./

# Copy environment file
COPY --chown=appuser:appuser .env.docker .env

# Switch to non-root user
USER appuser

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:8080/', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

# Run the application
CMD ["node", "server.js"]
