# ---- build stage ----
FROM node:18-bullseye AS build
WORKDIR /app

# Copy only what’s needed to install deps first
COPY package.json yarn.lock .yarnrc.yml .npmrc ./
COPY packages/backend/package.json packages/backend/
COPY packages/app/package.json packages/app/

# Use Yarn v4 via Corepack, and ensure npmjs
RUN corepack enable && corepack prepare yarn@4.9.4 --activate
ENV YARN_NPM_REGISTRY_SERVER=https://registry.npmjs.org

# Quick sanity: show Yarn & that the package exists
RUN yarn --version && yarn npm view @backstage/backend-defaults version

# Install dependencies (no network changes allowed)
RUN yarn install --immutable

# Now copy the rest and build
COPY . .
RUN yarn tsc
RUN npx --yes @backstage/cli backend:bundle --build-dependencies

# ---- runtime stage ----
FROM node:18-bullseye
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app/packages/backend/dist ./packages/backend/dist
COPY --from=build /app/packages/backend/package.json ./packages/backend/package.json
COPY --from=build /app/yarn.lock ./yarn.lock
RUN corepack enable && corepack prepare yarn@4.9.4 --activate \
 && yarn install --production --immutable --cwd packages/backend
EXPOSE 7007
CMD ["node", "packages/backend/dist/index.js"]
