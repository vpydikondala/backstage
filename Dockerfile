# ---------- build stage ----------
FROM node:20-bullseye AS build
WORKDIR /app

# 1) Copy only the files needed to install deps deterministically
COPY package.json yarn.lock .yarnrc.yml .npmrc ./
COPY packages/backend/package.json packages/backend/
# If you have an app workspace, this line is fine to keep; it won't break:
COPY packages/app/package.json packages/app/

# 2) Yarn 4 and exact install
RUN corepack enable && corepack prepare yarn@4.9.4 --activate
RUN yarn --version && npm --version
RUN yarn install --immutable

# 3) Now copy sources and compile only the backend TS (no bundling)
COPY . .
RUN yarn exec tsc -p packages/backend/tsconfig.json

# ---------- runtime stage ----------
FROM node:20-slim AS runner
WORKDIR /app
ENV NODE_ENV=production

# (Optional) Keep Yarn available at runtime for tooling parity
RUN corepack enable && corepack prepare yarn@4.9.4 --activate

# 4) Bring only what the backend needs to run
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/packages/backend/dist ./packages/backend/dist
COPY packages/backend/package.json packages/backend/package.json
# Bring your config(s) – adjust if you keep them elsewhere
COPY app-config*.yaml ./

EXPOSE 7007
CMD ["node", "packages/backend/dist/index.js", "--config", "app-config.yaml"]
