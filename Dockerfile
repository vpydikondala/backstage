# ---- build stage ----
FROM node:18-bullseye AS build
WORKDIR /app
COPY . .
RUN yarn install --frozen-lockfile
RUN yarn tsc
# Bundle backend AND include the frontend assets
RUN npx --yes @backstage/cli backend:bundle --build-dependencies

# ---- runtime stage ----
FROM node:18-bullseye
WORKDIR /app
ENV NODE_ENV=production
# copy only runtime bits
COPY --from=build /app/packages/backend/dist ./packages/backend/dist
COPY --from=build /app/packages/backend/package.json ./packages/backend/package.json
COPY --from=build /app/yarn.lock ./yarn.lock
RUN yarn install --production --frozen-lockfile --cwd packages/backend
EXPOSE 7007
CMD ["node", "packages/backend/dist/index.js"]
