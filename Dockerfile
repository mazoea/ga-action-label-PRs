FROM alpine:3.20
RUN apk add --no-cache curl jq bash
COPY --chmod=0755 entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
