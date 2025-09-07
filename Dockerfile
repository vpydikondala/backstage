FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json yarn.lock ./
RUN yarn install --frozen-lockfile
COPY . .
RUN yarn tsc:full && yarn build

FROM node:18-alpine
WORKDIR /app
COPY --from=builder /app/packages/backend ./backend
COPY --from=builder /app/packages/app ./app
WORKDIR /app/backend
RUN yarn install --production --frozen-lockfile
CMD ["node", "dist/index.js"]
EXPOSE 7007
