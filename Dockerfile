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
# This is the only Chrome in the container; server.js exposes its
# path as PUPPETEER_EXECUTABLE_PATH so Lighthouse and pa11y use it.
RUN npx playwright install --with-deps chromium

COPY . .

EXPOSE 3000
CMD ["node", "server.js"]
