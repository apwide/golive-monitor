#!/bin/bash

: "${API_KEY:=}"
: "${BASE_URL:=https://golive.apwide.net/api}"
: "${STATUS_UP:=Up}"
: "${STATUS_DOWN:=Down}"
: "${GOLIVE_QUERY:=}"
: "${URL_TO_CHECK:=}"
: "${JIRA_USERNAME:=}"
: "${JIRA_PASSWORD:=}"
: "${READ_ONLY:=}"

auth_header="Authorization: bearer ${API_KEY}"

function help_debug {
    cat <<END
To function properly this script requires some parameters passed as environment variables

*Cloud*

- API_KEY -- you can generate that key in the integration section of Golive

*Server/DC*

- JIRA_USERNAME
- JIRA_PASSWORD
- BASE_URL -- e.g https://my.jira.local/jira/rest/apwide/tem/1.1

*ALL*

The following are optional and their value depends on the configuration in Golive

- STATUS_UP - the name of the status in Golive you want to see when environments are up (defaults to 'Up')
- STATUS_DOWN - the name of the status in Golive you want to see when environments are up (defaults to 'Down')
- GOLIVE_QUERY - the query string to be used to filter the list of environment to be tested
                 e.g. applicationName=
- URL_TO_CHECK - be default, the environment 'url' value is tested, you can override this by adding an
                 environment attribute and pass it to this script

*Common pitfalls*

API_KEY of the JIRA credentials are wrong. Double check that the provided values are correct.

On server/DC, wrong password might result in the user being eligible for CAPTCHA if there were to many failures,
reset it in Jira's user management page before continuing with this script.

If fetching the environments works but the script cannot update statuses, it might be related to permissions.
This script uses the permissions of the user for each environment based on the assigned permission scheme
Check the permission of the user which was used to generate the API_KEY (or the user defined in JIRA_USERNAME before
server/DC).
END
}

function exit_with_message {
    help_debug
    echo >&2 -e "\nERROR: $1\n"
    exit 1
}

# Requirements
which jq >/dev/null 2>&1 || exit_with_message "jq is missing"
which curl >/dev/null 2>&1 || exit_with_message "curl is missing"

# Only one of me can run
if ps ax | grep "$0" | grep -v $$ | grep bash | grep -v grep
then
    echo "Already running... exiting."
    exit 1
fi

if [ "$API_KEY" = "" ] && [ "${JIRA_USERNAME}" == "" ]; then
    exit_with_message "API_KEY is missing"
fi

if [ "$BASE_URL" = "" ]; then
    exit_with_message "BASE_URL is missing, should be \n - 'https://golive.apwide.net/api' for cloud\n - 'https://my.jira.local/jira/rest/apwide/tem/1.1' for server/DC"
fi

if [ "$JIRA_USERNAME" != "" ] && [ "${JIRA_PASSWORD}" = '' ]; then
    exit_with_message "Missing JIRA_PASSWORD for user ${JIRA_USERNAME}."
fi

if [ "$JIRA_USERNAME" != "" ] && [ "${JIRA_PASSWORD}" != "" ]; then
    auth_header="Authorization: Basic $(echo -n "${JIRA_USERNAME}:${JIRA_PASSWORD}" | base64)"
fi

function check_if_up {
    local url=$1
    typeset -i response_code
    response_code=$(curl \
        -sL \
        --connect-timeout 5 \
        -w "%{http_code}\\n" \
        "${url}" \
        -o /dev/null \
        )

    if [ $response_code = 0 ]; then
        # domain not found
        echo $STATUS_DOWN
    elif [ $response_code -lt 400 ]; then
        echo $STATUS_UP
    else
        echo $STATUS_DOWN
    fi
}

function update_status {
    local env_id=$1
    local new_status=$2
    local response_code
    echo -n "Updating envId ${env_id} to ${new_status}... "

    if [ "${READ_ONLY}" = "true" ]; then
        echo "not done (\$READ_ONLY is true)"
    else

        response_code=$(
            curl -sL \
                -X PUT \
                -w "%{http_code}\\n" \
                -H "${auth_header}" \
                -H "Content-type: application/json" \
                -H "Accept: application/json" \
                -d "{ \"name\": \"$new_status\" }" \
                -o /dev/null \
                "${BASE_URL}/status-change?environmentId=${env_id}"
        )
        if [ $response_code = 304 ]; then
            echo "change was not needed (?)"
        elif [ $response_code = 200 ]; then
            echo "done"
        else
            echo "change was refused ($response_code)."
        fi
    fi
}

expand=false
if [ "$URL_TO_CHECK" != "" ]; then
    expand=true
fi

# Retrieve all environments
envs="$(mktemp)"
curl -sL -H "${auth_header}" "${BASE_URL}/environments/search/paginated?${GOLIVE_QUERY}&_expand=${expand}" >"${envs}"

if [ "$(cat "$envs")" = "" ]; then
    rm "$envs"
    exit_with_message "The provided host and/or key does not work properly. Please check your entries."
fi

if [ "${READ_ONLY}" = "true" ]; then
    echo "IMPORTANT: Running in read-only mode. Statuses will not be updated in Golive."
fi

typeset -i count
count=$(cat "$envs" | jq '.environments | length')
if [ $count -gt 1 ]; then
    echo "There are ${count} environments in Golive"
fi

((count = count - 1))

i=0
until [ $i -gt $count ]; do
    id="$(cat "$envs" | jq --argjson i $i '.environments[$i].id')"
    name="$(cat "$envs" | jq --argjson i $i '.environments[$i].name')"
    if [ "$URL_TO_CHECK" = "" ]; then
        url="$(cat "$envs" | jq -r --argjson i $i '.environments[$i].url')"
    else
        url="$(cat "$envs" | jq -r --argjson i $i --arg attr $URL_TO_CHECK '.environments[$i].attributes[$attr]')"
    fi
    if [ "$url" = '' ] || [ "$url" = 'null' ]; then
        echo "$name has no url"
    else
        echo "Testing $name on $url"
        new_status=$(check_if_up "$url")
        current_status="$(cat "$envs" | jq -r --argjson i $i '.environments[$i].status.name')"
        if [ "$current_status" != "$new_status" ]; then
            update_status "$id" "$new_status"
        fi
    fi
    ((i = i + 1))
done

rm -r "$envs"
