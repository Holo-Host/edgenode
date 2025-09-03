FROM cgr.dev/chainguard/wolfi-base

RUN apk update && apk add --no-cache --update-cache curl wget htop jq

SHELL ["/bin/sh", "-c"]

CMD curl -s https://api.adviceslip.com/advice --http1.1 | jq .slip.advice
