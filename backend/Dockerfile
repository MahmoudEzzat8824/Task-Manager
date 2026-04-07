FROM node:22-bookworm-slim AS build

WORKDIR /app

# Install production dependencies only.
COPY package*.json ./
RUN npm ci --omit=dev

# Copy app source.
COPY . .

FROM gcr.io/distroless/nodejs20-debian12

WORKDIR /app

COPY --from=build --chown=nonroot:nonroot /app /app

ENV NODE_ENV=production
USER nonroot
EXPOSE 5000

CMD ["src/server.js"]