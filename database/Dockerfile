# Production-ready MongoDB Dockerfile
FROM mongo:7.0

# Set MongoDB environment variables
# These can be overridden at runtime via environment variables
ENV MONGO_INITDB_ROOT_USERNAME=${MONGO_INITDB_ROOT_USERNAME:-}
ENV MONGO_INITDB_ROOT_PASSWORD=${MONGO_INITDB_ROOT_PASSWORD:-}
ENV MONGO_INITDB_DATABASE=${MONGO_INITDB_DATABASE:-wanderlust}

# Create directory for initialization scripts (optional)
# If you have init scripts, place them in the database directory
# and uncomment the COPY line below
RUN mkdir -p /docker-entrypoint-initdb.d

# Copy initialization scripts if they exist (optional)
# COPY init-mongo.js /docker-entrypoint-initdb.d/

# Expose MongoDB port
EXPOSE 27017

# Health check to verify MongoDB is running
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD mongosh --eval "db.adminCommand('ping')" || exit 1

# Note: The official mongo image already has proper ENTRYPOINT configured
# It handles mongod startup with appropriate settings
# No need to override unless you need custom MongoDB configuration
