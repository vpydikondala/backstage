# ---------- build stage ----------
FROM node:20-bullseye AS build
WORKDIR /app

# Yarn 4
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0
RUN corepack enable && corepack prepare yarn@4.9.4 --activate

# Copy the entire repo so Yarn sees the exact same workspace layout as when the lockfile was generated
COPY . .

# Install exactly as locked
RUN yarn --version && npm --version
RUN yarn install --immutable

# Type-check/build BACKEND ONLY (avoid frontend DOM/JSX issues)
# assumes you added packages/backend/tsconfig.json as discussed
RUN yarn tsc -p packages/backend/tsconfig.json

# Bundle the backend with the CLI version you have in devDependencies
# (adjust the version if your root devDependency differs)
RUN npx --yes @backstage/cli@0.26.11 backend:bundle --build-dependencies

# ---------- runtime stage ----------
FROM node:20-slim AS runner
WORKDIR /app
ENV NODE_ENV=production

# Copy the backend bundle produced by the build stage
# The CLI writes a self-contained bundle under packages/backend/dist
COPY --from=build /app/packages/backend/dist /app

# Expose the typical Backstage backend port
EXPOSE 7007

# Start the bundled backend (entrypoint produced by the bundle step)
CMD ["node", "/app/index.cjs"]
