FROM node:20-slim

# Tools needed by security checks
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    openssl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Node deps before copying source (better layer caching)
COPY package*.json ./
RUN npm ci

# Pin browser install to a fixed path so the entrypoint can find it
# reliably regardless of HOME or the runtime user.
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
RUN npx playwright install --with-deps chromium

COPY . .

RUN chmod +x docker-entrypoint.sh

EXPOSE 3000
ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["node", "server.js"]
