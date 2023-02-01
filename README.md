# Golive monitor

This script performs the following operations:

- fetches environments from [Golive](https://marketplace.atlassian.com/apps/1212239/?tab=overview&hosting=cloud) (server or cloud)
- tests the availability of each environment (using `url` or using the environment value associated with an attribute name provided)
- perform status-change of each environment that has changed status (use DRY_RUN=true to avoid)

See the `help_debug` function for help configuration this script.

# Usage

We provide 2 ways of using this script:

- as a bash script
- as a docker image

## Script

To run/test locally:

```shell
export $(cat .env.server .env.server.local | grep -v "^#" | xargs) && ./golive-monitor.sh
```

## Docker image

### Build it locally

```shell
# build the image
$ docker build -t apwide/golive-monitor .
```

### Run it once.

To run it once:

```shell
$ docker run -ti -env-file=.env.server.local apwide/golive-monitor ./golive-monitor.sh
```

### Let it run by defining the period

Define a value in minutes for `PERIOD` environment variable.

```shell
$ docker run -ti -env-file=.env.server.local apwide/golive-monitor
```

In this configuration, if the previous execution is still running, the new run is postponed until the next minute.

## Configuration

- JIRA_USERNAME (only server/DC)
- JIRA_PASSWORD (only server/DC)
- BASE_URL (only server/DC)
- API_KEY (only cloud)
- STATUS_UP (default: 'Up') -- status value in golive for an environment to be seen as UP
- STATUS_DOWN (default: 'Down) -- status value in golive for an environment to be seen as DOWN
- GOLIVE_QUERY (optional) -- query string to filter the environment search
- URL_TO_CHECK (optional) -- attribute value to look for a test url, if not provided the environment url is used
- IGNORED_STATUSES (optional) -- comma separated list of status. If the environment has this status, it will not be checked
- DRY_RUN (optional) -- set to `true` to not update the status after the test
- PERIOD (default to 1) -- amount of minutes between to run when using the docker image as cron, cannot be smaller than one

### Examples

Cloud setup and filtering on category `Dev` and application `Payment`.

```shell
API_KEY=xxx
GOLIVE_QUERY=categoryName=Dev&application=Payment
```

Same but ignoring environments that has status set to None or Maintenance

```shell
API_KEY=xxx
GOLIVE_QUERY=categoryName=Dev&application=Payment
IGNORED_STATUSES=Maintenance,None
```

Same but using an environment attribute named `heartbeat` to check instead of the url

```shell
API_KEY=xxx
GOLIVE_QUERY=categoryName=Dev&application=Payment
IGNORED_STATUSES=Maintenance,None
URL_TO_CHECK=heartbeat
```

Same but disallow the script to update the statuses (useful to test the setup)

```shell
API_KEY=xxx
GOLIVE_QUERY=categoryName=Dev&application=Payment
IGNORED_STATUSES=Maintenance,None
URL_TO_CHECK=heartbeat
DRY_RUN=true
```

