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
: "${IGNORED_STATUSES:=}"
: "${USER_AGENT:=GoliveMonitor}"
: "${USE_PING:=}"

auth_header="Authorization: bearer ${API_KEY}"

SEARCH_PATH=/environments/search/paginated

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
- IGNORED_STATUSES - comma separated list of statuses. If an environment is in that status, the check will
                     not be performed. Values are not trimmed so be careful (ex. "Maintenance,None")
- USE_PING - set to 'true' to ping the host instead of doing an HTTP check (applies to all environments), IGNORED_STATUSES is ignored in ping mode

*Common pitfalls*

API_KEY or the JIRA credentials are wrong. Double check that the provided values are correct.

On server/DC, wrong password might result in the user being eligible for CAPTCHA if there were to many failures,
reset it in Jira's user management page before continuing with this script.

If fetching the environments works but the script cannot update statuses, it might be related to permissions.
This script uses the permissions of the user for each environment based on the assigned permission scheme
Check the permission of the user which was used to generate the API_KEY (or the user defined in JIRA_USERNAME before
server/DC).

The machine running this script must also be able to talk to Golive. For Cloud, it means golive.apwide.net must be reachable.

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
if [ "$USE_PING" = true ]; then
    which ping >/dev/null 2>&1 || exit_with_message "ping is missing"
fi

# Only one of me can run
me=$(basename "${BASH_SOURCE[0]}")

if which pidof > /dev/null 2>&1; then
    if pidof -o %PPID -x "${me}" >/dev/null 2>&1; then
        echo "Already running... exiting."
        exit
    fi
else
    # this fails in docker on MacOS... hence the use of pidof if available
    if command ps ax | grep "$me" | grep -v $$ | grep -v grep >/dev/null; then
        echo "Already running... exiting"
        exit
    fi
fi

if test -z "$BASE_URL"; then
    exit_with_message "BASE_URL is missing, should be \n - 'https://golive.apwide.net/api' for cloud\n - 'https://my.jira.local/jira/rest/apwide/tem/1.1' for server/DC"
fi

if test -z "$API_KEY" && test -z "$JIRA_USERNAME"; then
    exit_with_message "API_KEY is missing"
fi

if test "$JIRA_USERNAME" && test -z "$JIRA_PASSWORD"; then
    exit_with_message "Missing JIRA_PASSWORD for user $JIRA_USERNAME."
fi

declare -a curl_params

if test "$JIRA_USERNAME" && test "$JIRA_PASSWORD"; then
    curl_params+=(-H "Authorization: Basic $(printf '%s:%s' "$JIRA_USERNAME" "$JIRA_PASSWORD" | base64)")
else
    curl_params+=(-H "Authorization: bearer $API_KEY")
fi

curl_params+=(--user-agent "Golive Monitor")

if test -n "$API_KEY" && test -z "$JIRA_USERNAME"; then
    IFS='.' read -ra token_split <<< "$API_KEY"
    golive_key=$(echo "${token_split[1]}" | base64 -d | jq -r '.goliveKey')
    user_account_id=$(echo "${token_split[1]}" | base64 -d | jq -r '.userAccountId')
    if test -n "$golive_key"; then
        curl_params+=(-H "X-Apw-Golive-Key: $golive_key")
    fi
    if test -n "$user_account_id"; then
        curl_params+=(-H "X-Apw-Account-Id: $user_account_id")
    fi
fi

# Handle the case of Golive not reachable
if ! curl "${curl_params[@]}" "$BASE_URL" > /dev/null 2>/dev/null; then
    exit_with_message "$BASE_URL is not reachable from this host"
fi

# Handle the not 200 case
code=$(curl -s -o /dev/null -w '%{http_code}' "${curl_params[@]}" "$BASE_URL$SEARCH_PATH?_limit=1")

if [ "$code" != "200" ]; then
    exit_with_message "API_KEY or JIRA_USERNAME/JIRA_PASSWORD do not work, server returned $code"
fi

function check_if_up {
    local url=$1
    local response_code
    typeset -i response_code
    response_code=$(
        curl \
            -sL \
            --user-agent "$USER_AGENT" \
            --connect-timeout 5 \
            -w "%{http_code}\\n" \
            "${url}" \
            -o /dev/null
    )

    if [ $response_code -eq 0 ]; then
        # domain not found
        echo "$STATUS_DOWN"
    elif [ $response_code -lt 400 ]; then
        echo "$STATUS_UP"
    else
        echo "$STATUS_DOWN"
    fi
}

# Extract a host (domain or IP) from an input that can be:
# - a domain (e.g., example.org)
# - an IP (e.g., 10.0.0.1)
# - a URL (e.g., https://example.org:8443/path?q=1)
function extract_host() {
    local input=$1
    local host
    # If it looks like a URL (has scheme://), strip scheme and take up to first '/'
    if [[ "$input" =~ ^[a-zA-Z][a-zA-Z0-9+.-]*:// ]]; then
        host=${input#*://}
        host=${host%%/*}
    else
        host=$input
    fi
    # Remove optional port if present (host:port)
    host=${host%%:*}
    echo "$host"
}

# Ping-based availability check mirroring check_if_up behavior
# Returns STATUS_UP when the host replies to a single ICMP echo request, otherwise STATUS_DOWN
function check_if_up_ping() {
    local target=$1
    local host
    host=$(extract_host "$target")
    if [ -z "$host" ] || [ "$host" = "null" ]; then
        echo "$STATUS_DOWN"
        return
    fi
    # Send a single ping and rely on the return code
    if ping -c 1 -W 3 "$host" >/dev/null 2>&1; then
        echo "$STATUS_UP"
    else
        echo "$STATUS_DOWN"
    fi
}

function update_status {
    local env_id=$1
    local new_status=$2
    local response_code
    typeset -i response_code

    printf 'Updating envId %d to %s... ' "$env_id" "$new_status"

    if [ "$DRY_RUN" = "true" ]; then
         printf "not done (DRY_RUN is true)\n"
    else
        response_code=$(
            curl -s \
                -X PUT \
                -w "%{http_code}\\n" \
                "${curl_params[@]}" \
                -H "Content-type: application/json" \
                -H "Accept: application/json" \
                -d "{ \"name\": \"$new_status\" }" \
                -o /dev/null \
                "$BASE_URL/status-change?environmentId=$env_id"
        )
        if [ $response_code = 304 ]; then
            printf "change was not needed (?)\n"
        elif [ $response_code = 200 ]; then
            printf "done\n"
        else
            printf 'change was refused (%s)\n' "$response_code"
        fi
    fi
}

function is_ignored_status {
    if [ "$IGNORED_STATUSES" = "" ]; then
        return 1
    else
        local status=$1
        local list
        local i
        list=$(echo "$IGNORED_STATUSES" | tr ',' ' ')
        for i in $list; do
            if [ "$i" = "$status" ]; then
                return 0
            fi
        done
        return 1
    fi
}

expand=false
if [ "$URL_TO_CHECK" != "" ]; then
    expand=true
fi
if test "$READ_ONLY" = "true"; then
    echo "Runing in read only to check the server response."
    echo "setup:"
    echo " ➙ url: $BASE_URL ($SEARCH_PATH)"
    echo " ➙ query: \"$GOLIVE_QUERY\" (can be empty)"
    echo "We will query the server and send the output through jq:"
    curl -s "${curl_params[@]}" "$BASE_URL$SEARCH_PATH?$GOLIVE_QUERY&_expand=$expand" | jq
    echo "if the above text is a JSON object, you can probably remove the READ_ONLY variable by removing it from the .env file AND remove it from the running shell."
    exit
fi


# Retrieve all environments
envs="$(mktemp)"
curl -s "${curl_params[@]}" "$BASE_URL$SEARCH_PATH?$GOLIVE_QUERY&_expand=$expand" > "$envs"

if test ! -s "$envs" || test "$(jq < "$envs" -r type)" != "object"; then
    exit_with_message "Your golive credentials are good, but the server returned something weird.\n \
        - the url used: \"$BASE_URL$SEARCH_PATH?$GOLIVE_QUERY&_expand=$expand\" \n \
        - the returned content \"$(cat "$envs")\" \n \
        - this content is stored in this file \"$envs\" \n \
        the content should be a JSON object."

fi

if [ "$DRY_RUN" = "true" ]; then
    echo "IMPORTANT: Running in read-only mode. Statuses will not be updated in Golive."
fi

typeset -i count
count=$(jq < "$envs" '.environments | length')
if [ $count -gt 1 ]; then
    printf "There are %s environments in Golive\n" "${count}"
fi

if [ $count -eq 0 ]; then
    echo "Nothing to do, there are no environments."
fi

((count = count - 1))

index=0
until [ $index -gt $count ]; do
    id="$(jq < "$envs" -r --argjson index $index '.environments[$index].id')"
    name="$(jq < "$envs" -r --argjson index $index '.environments[$index].name')"
    current_status="$(jq < "$envs" -r --argjson index $index '.environments[$index].status.name')"

    if [ "$current_status" = "null" ]; then
        current_status=None
    fi

    if is_ignored_status "$current_status"; then
        printf 'Ignoring %s as its status is %s\n' "$name" "$current_status"
    else
        if [ "$URL_TO_CHECK" = "" ]; then
            url="$(jq < "$envs" -r --argjson index $index '.environments[$index].url')"
        else
            url="$(jq < "$envs" -r --argjson index $index --arg attr "$URL_TO_CHECK" '.environments[$index].attributes[$attr]')"
        fi
        if [ "$url" = '' ] || [ "$url" = 'null' ]; then
            printf '%s (%d) has no url\n' "$name" "$id"
        else
            if [ "$USE_PING" = "true" ]; then
                host_to_ping=$(extract_host "$url")
                printf 'Pinging %s (%d) host %s (from %s)...' "$name" "$id" "$host_to_ping" "$url"
                new_status=$(check_if_up_ping "$url")
            else
                printf 'Testing %s (%d) via HTTP on %s...' "$name" "$id" "$url"
                new_status=$(check_if_up "$url")
            fi
            if [ "$current_status" != "$new_status" ]; then
                printf ' now "%s"\n' "$new_status"
                update_status "$id" "$new_status"
            else
                printf ' still "%s"\n' "$new_status"
            fi
        fi
    fi
    ((index = index + 1))
done

rm -r "$envs"
