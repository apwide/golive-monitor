# Golive monitor

This script performs the following operations:

-   fetches environments from [Golive](https://marketplace.atlassian.com/apps/1212239/?tab=overview&hosting=cloud) (server or cloud)
-   tests the availability of each environment (default via HTTP against `url` or an attribute, or via ICMP ping when using the `USE_PING=true` environment variable)
-   perform status-change of each environment that has changed status (use DRY_RUN=true to avoid)

Use READ_ONLY=true to test without updating anything on Golive.

# Usage

We provide 2 ways of using this script:

-   as a bash script
-   as a docker image

## Script

### Setup

First, copy the example environment file and configure it for your setup:

```shell
cp .env.example .env
```

Then edit `.env` with your specific configuration values (see Configuration section below).

### Run locally

To run/test locally:

```shell
env $(cat .env | grep -v "^#" | xargs) ./golive-monitor.sh
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
$ docker run -ti --env-file=.env apwide/golive-monitor ./golive-monitor.sh
```

OR just set `PERIOD=0` and run without the command

```shell
$ docker run -ti --env-file=.env apwide/golive-monitor
```

When testing this image localy, remember that running container usualy cannot access `localhost`, make `BASE_URL` points to an IP or a resolvable machine name.


### Let it run by defining the period

Define a value in minutes for `PERIOD` environment variable.

```shell
$ docker run -ti --env-file=.env apwide/golive-monitor
```

In this configuration, if the previous execution is still running, the new run is postponed until the next minute.

## Ping vs HTTP modes

- HTTP (default): the script performs an HTTP request to the environment URL (or to the value of the attribute named by `URL_TO_CHECK`) and considers it Up when the HTTP status code is < 400.
- Ping (set `USE_PING=true`): the script extracts the host from the environment URL/attribute (URL, domain or IP) and sends a single ICMP echo (`ping -c 1`). If the command succeeds, the environment is considered Up; otherwise Down. This applies to all environments for the run.

Run with ping mode:

```shell
USE_PING=true ./golive-monitor.sh
```

Run with default HTTP mode:

```shell
./golive-monitor.sh
```

When used as a Docker image, set the env variable in the `.env` file.

## Configuration

Copy `.env.example` to `.env` and configure the appropriate variables for your setup:

### Cloud Configuration
-   **API_KEY** (required) -- Generate it in the Golive integrations page

### Server/DC Configuration
-   **JIRA_USERNAME** (required) -- Your Jira username
-   **JIRA_PASSWORD** (required) -- Your Jira password
-   **BASE_URL** (required) -- Jira REST API base URL (e.g., http://localhost:2990/jira/rest/apwide/tem/1.1)

### Optional Settings (both cloud and server)
-   **STATUS_UP** (default: 'Up') -- status value in golive for an environment to be seen as UP
-   **STATUS_DOWN** (default: 'Down') -- status value in golive for an environment to be seen as DOWN
-   **GOLIVE_QUERY** (optional) -- query string to filter the environment search
-   **URL_TO_CHECK** (optional) -- attribute value to look for a test url, if not provided the environment url is used
-   **IGNORED_STATUSES** (optional) -- comma separated list of status. If the environment has this status, it will not be checked
-   **DRY_RUN** (optional) -- set to `true` to not update the status after the test
-   **PERIOD** (default to 1) -- amount of minutes between runs when using the docker image as cron, cannot be smaller than one
-   **READ_ONLY** (optional) -- set to `true` to stop after fetching the environments from Golive (perfect to troubleshoot your configuration)
-   **USE_PING** (optional) -- runs ping test instead of HTTP

### Examples

#### Cloud Setup
For Atlassian Cloud, configure only the cloud section in your `.env` file:

```shell
# =============================================================================
# CLOUD CONFIGURATION
# =============================================================================

# Generate it in the Golive integrations page
API_KEY=your_api_key_here

# Optional settings can be added below
# DRY_RUN=true
# GOLIVE_QUERY=categoryName=Dev
```

#### Server/DC Setup
For Jira Server or Data Center, configure only the server section in your `.env` file:

```shell
# =============================================================================
# SERVER CONFIGURATION
# =============================================================================

JIRA_USERNAME=admin
JIRA_PASSWORD=admin
BASE_URL=http://localhost:2990/jira/rest/apwide/tem/1.1

# remove or assign another value to enable status-changes
DRY_RUN=true
```

#### Advanced Cloud Configuration Examples

Cloud setup with filtering on category `Dev` and application `Payment`:

```shell
# =============================================================================
# CLOUD CONFIGURATION
# =============================================================================

API_KEY=your_api_key_here
GOLIVE_QUERY=categoryName=Dev&application=Payment
```

With ignored statuses (environments with status 'None' or 'Maintenance' won't be checked):

```shell
# =============================================================================
# CLOUD CONFIGURATION
# =============================================================================

API_KEY=your_api_key_here
GOLIVE_QUERY=categoryName=Dev&application=Payment
IGNORED_STATUSES=Maintenance,None
```

Using a custom environment attribute named `heartbeat` for health checks:

```shell
# =============================================================================
# CLOUD CONFIGURATION
# =============================================================================

API_KEY=your_api_key_here
GOLIVE_QUERY=categoryName=Dev&application=Payment
IGNORED_STATUSES=Maintenance,None
URL_TO_CHECK=heartbeat
```

Dry run mode (test configuration without updating statuses):

```shell
# =============================================================================
# CLOUD CONFIGURATION
# =============================================================================

API_KEY=your_api_key_here
GOLIVE_QUERY=categoryName=Dev&application=Payment
IGNORED_STATUSES=Maintenance,None
URL_TO_CHECK=heartbeat
DRY_RUN=true
```

