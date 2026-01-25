# Stage 1: Build Stage
FROM node:21 AS frontend-builder

# Accept build argument for API URL (domain-based)
ARG VITE_API_PATH=https://api.wanderlust.example.com

# Set as environment variable for Vite build
ENV VITE_API_PATH=${VITE_API_PATH}

# Set the working directory
WORKDIR /app

# Copy package files for better layer caching
COPY package*.json ./

# Install dependencies
RUN npm ci

# Copy source code
COPY . .

# Build the application for production (Vite will use VITE_API_PATH from env)
RUN npm run build

# Stage 2: Production Stage
FROM nginx:alpine

# Create a non-root user (nginx runs as nginx user by default in alpine)
# Copy built assets from builder stage
COPY --from=frontend-builder /app/dist /usr/share/nginx/html

# Create nginx configuration for SPA routing
RUN echo 'server { \
    listen 80; \
    server_name _; \
    root /usr/share/nginx/html; \
    index index.html; \
    \
    # Gzip compression \
    gzip on; \
    gzip_vary on; \
    gzip_min_length 1024; \
    gzip_types text/plain text/css text/xml text/javascript application/x-javascript application/xml+rss application/javascript application/json; \
    \
    # Security headers \
    add_header X-Frame-Options "SAMEORIGIN" always; \
    add_header X-Content-Type-Options "nosniff" always; \
    add_header X-XSS-Protection "1; mode=block" always; \
    \
    # SPA routing - serve index.html for all routes \
    location / { \
        try_files $uri $uri/ /index.html; \
    } \
    \
    # Cache static assets \
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ { \
        expires 1y; \
        add_header Cache-Control "public, immutable"; \
    } \
}' > /etc/nginx/conf.d/default.conf

# Expose port 80
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost/ || exit 1

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
