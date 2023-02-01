FROM alpine:latest

RUN apk add jq curl dumb-init bash
RUN mkdir "/app"
WORKDIR /app

COPY golive-monitor.sh .
COPY cron.sh .

RUN chmod +x golive-monitor.sh cron.sh

RUN crontab -l | { cat; echo "* * * * * bash /app/cron.sh"; } | crontab -

CMD ["dumb-init", "crond",  "-f" ]
