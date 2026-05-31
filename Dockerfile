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

# Install Playwright's Chromium + all required system libraries.
# docker-entrypoint.sh resolves its path at startup and exports
# CHROME_PATH + PUPPETEER_EXECUTABLE_PATH for Lighthouse and pa11y.
RUN npx playwright install --with-deps chromium

COPY . .

RUN chmod +x docker-entrypoint.sh

EXPOSE 3000
ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["node", "server.js"]
