# --- Build stage -------------------------------------------------------------
FROM node:20-bullseye AS build
WORKDIR /app

# Copy only manifests first (faster, better layer caching)
COPY package.json yarn.lock .yarnrc.yml .npmrc ./
COPY packages/backend/package.json packages/backend/
COPY packages/app/package.json packages/app/

RUN corepack enable && corepack prepare yarn@4.9.4 --activate
RUN yarn --version && npm --version

# Install deps exactly as locked
RUN yarn install --immutable

# Now copy the rest of the source
COPY . .

# Type-check/compile
RUN yarn tsc

# Bundle the backend (adjust CLI version here to match your root devDep)
RUN npx --yes @backstage/cli@0.26.11 backend:bundle --build-dependencies

# --- Runtime stage -----------------------------------------------------------
FROM node:20-slim
ENV NODE_ENV=production
WORKDIR /app

# Copy backend bundle and config
COPY --from=build /app/packages/backend/dist ./packages/backend/dist
COPY --from=build /app/app-config*.yaml ./

EXPOSE 7007
CMD ["node", "packages/backend/dist/bundle.cjs"]
