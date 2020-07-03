
# Library of utility functions for manipulating/controling bash-internals
# Not intended to be executed directly

source $(dirname $(realpath "${BASH_SOURCE[0]}"))/console_output.sh

copy_function() {
    local src="$1"
    local dst="$2"
    [[ -n "$src" ]] || \
        die "Expecting source function name to be passed as the first argument"
    [[ -n "$dst" ]] || \
        die "Expecting destination function name to be passed as the second argument"
    src_def=$(declare -f "$src") || [[ -n "$src_def" ]] || \
        die "Unable to find source function named ${src}()"
    dbg "Copying function ${src}() to ${dst}()"
    # First match of $src replaced by $dst
    eval "${src_def/$src/$dst}"
}

rename_function() {
    local from="$1"
    local to="$2"
    [[ -n "$from" ]] || \
        die "Expecting current function name to be passed as the first argument"
    [[ -n "$to" ]] || \
        die "Expecting desired function name to be passed as the second argument"
    dbg "Copying function ${from}() to ${to}() before unlinking ${from}()"
    copy_function "$from" "$to"
    dbg "Undefining function $from"
    unset -f "$from"
}

# Return 0 if the first argument matches any subsequent argument exactly
# otherwise return 1.
contains() {
    local needle="$1"
    local hay  # one piece of the stack at a time
    shift
    #dbg "Looking for '$1' in '$@'"
    for hay; do [[ "$hay" == "$needle" ]] && return 0; done
    return 1
}

# Retry a command on a particular exit code, up to a max number of attempts,
# with exponential backoff.
#
# Usage: err_retry <attempts> <sleep ms> <exit_code> <command> <args>
# Where:
#   attempts: The number of attempts to make.
#   sleep ms: Number of miliseconds to sleep (doubles every attempt)
#   exit_code: Space separated list of exit codes to retry. If empty
#              then any non-zero code will be considered for retry.
#
# When the number of attempts is exhausted, exit code is 126 is returned.
#
# N/B: Make sure the exit_code argument is properly quoted!
#
# Based on work by 'Ayla Ounce <reacocard@gmail.com>' available at:
# https://gist.github.com/reacocard/28611bfaa2395072119464521d48729a
function err_retry() {
    local rc=0
    local attempt=0
    local attempts="$1"
    local sleep_ms="$2"
    local -a exit_codes
    ((attempts>1)) || \
        die "It's nonsense to retry a command less than twice, or '$attempts'"
    ((sleep_ms>0)) || \
        die "Refusing idiotic sleep interval of $sleep_ms"
    local zzzs=$(awk -e '{printf "%f", $1 / 1000}'<<<"$sleep_ms")
    local nzexit=0  #false
    local dbgspec="[${exit_codes[@]}]"
    if [[ -z "$3" ]]; then
        nzexit=1;  # true
        dbgspec="non-zero"
    else
        exit_codes=("${3}")
    fi

    shift 3

    dbg "Will retry $attempts times, sleeping up to $zzzs*2^$attempts or exit code(s) $dbgspec."
    for attempt in $(seq 1 $attempts); do
        msg "Attempt $attempt of $attempts:"
        ( # Make each attempt easy to distinguish
            echo -n "+ "; printf '%q\n' "${@}"  # Make bad command easy to spot
            "$@" && rc=$? || rc=$?  # work with set -e or +e
            msg "exit($rc)"  # Make easy to debug

            if ((nzexit!=0)) && ((rc==0)); then
                dbg "Success! $rc==0"
                return 0
            elif ((nzexit)) || contains $rc ${exit_codes[@]}; then
                dbg "Success! ($rc in [${exit_codes[@]}])"
                return $rc
            elif ((attempt<attempts))  # No sleep on last failure
            then
                dbg "Failure! Sleeping $zzzs"
                sleep "$zzzs"
            fi
        ) |& indent 1
        zzzs=$(awk -e '{printf "%f", $1 + $1}'<<<"$zzzs")
    done
    msg "Retry attempts exhausted"
    return 126
}
