# ---------- build ----------
FROM node:20-bullseye AS build
WORKDIR /app

# 1) Copy manifests & configs first
COPY package.json yarn.lock .npmrc .yarnrc.yml ./
COPY packages/backend/package.json packages/backend/
COPY packages/app/package.json packages/app/

# 2) Use Yarn 4
RUN corepack enable && corepack prepare yarn@4.9.4 --activate
ENV YARN_NPM_REGISTRY_SERVER=https://registry.npmjs.org

# (optional) quick sanity – change or remove the next line
RUN yarn --version && npm view @backstage/backend-defaults version

# 3) Install deps from lockfile
RUN yarn install --immutable

# 4) Copy source & build
COPY . .
RUN yarn tsc
RUN npx --yes @backstage/cli backend:bundle --build-dependencies

# ---------- runtime ----------
FROM node:20-bullseye
WORKDIR /app
ENV NODE_ENV=production

COPY --from=build /app/packages/backend/dist ./packages/backend/dist
COPY --from=build /app/packages/backend/package.json ./packages/backend/package.json
COPY --from=build /app/yarn.lock ./yarn.lock

RUN corepack enable && corepack prepare yarn@4.9.4 --activate \
  && yarn workspaces focus --all --production

EXPOSE 7007
CMD ["node", "packages/backend/dist/index.js"]
