# Golive monitor

Currently Golive monitor is only provided as a Bash script.

This script performs the following operations:

- fetches environments from [Golive](https://marketplace.atlassian.com/apps/1212239/?tab=overview&hosting=cloud) (server or cloud)
- tests the availability of each environment (using `url` or using the environment value associated with an attribute name provided)
- perform status-change of each environment that has changed status (use DRY_RUN=true to avoid)

See the `help_debug` function for help configuration this script.

To run/test locally:

```shell
export $(cat .env.server .env.server.local | grep -v "^#" | xargs) && ./golive-monitor.sh
```
