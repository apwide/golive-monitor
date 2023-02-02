FROM alpine:latest

RUN apk add jq curl dumb-init bash
RUN mkdir "/app"
WORKDIR /app

COPY *.sh ./

RUN chmod +x golive-monitor.sh cron.sh start.sh


CMD ["dumb-init", "/app/start.sh" ]
