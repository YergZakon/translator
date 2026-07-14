# syntax=docker/dockerfile:1.7

ARG NODE_IMAGE=node:22-bookworm-slim

FROM ${NODE_IMAGE} AS pnpm-base
ENV PNPM_HOME=/pnpm
ENV PATH=${PNPM_HOME}:${PATH}
WORKDIR /app

RUN corepack enable && corepack prepare pnpm@11.7.0 --activate

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/backend/package.json apps/backend/package.json

FROM pnpm-base AS build
RUN pnpm install --frozen-lockfile

COPY apps/backend apps/backend
RUN pnpm typecheck && pnpm test && pnpm build

FROM pnpm-base AS production-dependencies
ENV NODE_ENV=production
RUN pnpm install --frozen-lockfile --prod

FROM ${NODE_IMAGE} AS runtime
ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=3000
WORKDIR /app

COPY --from=production-dependencies --chown=node:node /app/node_modules ./node_modules
COPY --from=production-dependencies --chown=node:node /app/apps/backend/node_modules ./apps/backend/node_modules
COPY --from=build --chown=node:node /app/apps/backend/dist ./apps/backend/dist
COPY --chown=node:node apps/backend/migrations ./apps/backend/migrations
COPY --chown=node:node apps/backend/package.json ./apps/backend/package.json

WORKDIR /app/apps/backend
USER node
EXPOSE 3000
STOPSIGNAL SIGTERM

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["node", "-e", "fetch('http://127.0.0.1:' + (process.env.PORT || '3000') + '/v1/health').then((response) => process.exit(response.ok ? 0 : 1)).catch(() => process.exit(1))"]

CMD ["node", "dist/server.js"]
