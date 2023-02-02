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

/app/cron.sh

if [ $PERIOD -eq 0 ]; then
    exit
fi

printf "\n\nInstalling cron schedule..."

crontab -l | { cat; echo "* * * * * bash /app/cron.sh"; } | crontab -

if [ $? = 0 ]; then
    printf " done\n"
else
    printf " failed to install\n"
    exit 1
fi

printf "\nStarting crond\n\n"

crond -f
