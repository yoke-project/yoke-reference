# The container this repository defines for its own build.
# It installs a runner; the floor that runner must meet is declared by the workspace.
FROM docker.io/library/golang:1.26-bookworm
ARG JUST_VERSION=1.58.0
# The reference web client runs on Node.js, taken whole from its own image.
COPY --from=docker.io/library/node:24-bookworm-slim /usr/local/bin/node /usr/local/bin/node
COPY --from=docker.io/library/node:24-bookworm-slim /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm
RUN curl -fsSL https://just.systems/install.sh | bash -s -- --tag "${JUST_VERSION}" --to /usr/local/bin
WORKDIR /src
COPY . .
