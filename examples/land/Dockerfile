# Build the static site; site/ is supplied by the private land repository.
FROM klakegg/hugo:0.111.3-ext-alpine AS builder
WORKDIR /src
COPY . .
RUN hugo --source=/src/site --destination=/out

FROM caddy:2-alpine
COPY --from=builder /out /usr/share/caddy
