# ---- build stage ----
FROM node:18-bullseye AS build
WORKDIR /app

# 1) Copy only files needed for dependency install first for better caching
COPY .yarnrc.yml ./
COPY .yarn ./.yarn
COPY package.json yarn.lock ./
COPY packages/backend/package.json packages/backend/
COPY packages/app/package.json packages/app/

# 2) Ensure corepack is enabled so Yarn v4 from .yarnrc.yml is used
RUN corepack enable

# 3) Install deps (Yarn v4 flags)
#    Force npmjs registry in case .yarnrc.yml isn't honored in your env
ENV YARN_NPM_REGISTRY_SERVER=https://registry.npmjs.org
RUN yarn --version && yarn install --immutable

# 4) Copy the rest of the source & build
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
RUN corepack enable && yarn install --production --immutable --cwd packages/backend
EXPOSE 7007
CMD ["node", "packages/backend/dist/index.js"]
