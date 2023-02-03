#!/bin/bash

: "${PERIOD:=1}"

cat <<END

                    #####
                 ###########                Apwide Golive monitor
               .####     ####.
              ####.       ,####             Stand tight while we:
             ####    ###    ####
           ####(   .#####    *####          - Prepare first run
          ####    ##/  .###    ####         - Setup cron
        /####     ,#########    ####*       - start cron
       ####    ####/     .####    ####
     *####    #################    ####
    ####                           (###
  ,####     ##########################
 #/      #########################/
END

if ! /app/cron.sh; then
    exit 1
fi

if [ "$PERIOD" -eq 0 ]; then
    exit
fi

printf "\n\nInstalling cron schedule..."

if crontab -l | { cat; echo "* * * * * bash /app/cron.sh"; } | crontab -; then
    printf " done\n"
else
    printf " failed to install\n"
    exit 1
fi

printf "\nStarting crond\n\n"

crond -f
