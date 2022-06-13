#!/usr/bin/env bash

declare pids=()

declare name=""
declare debug=0
declare version=""

function init_sequence () {
  echo 0 | tee sequence >/dev/null
}

function next_sequence () {
  # shellcheck disable=SC2155
  local seq="$(cat sequence)"
  echo $(( seq + 1 )) | tee sequence
}

function parse_command_line_arguments () {
  while (( $# > 0 )); do
    arg="$1"
    shift

    if [ "--" == "${arg:0:2}" ]; then
      arg="${arg:2}"

      for (( i = 0; i < ${#arg}; ++i )); do
        ## look for '='
        if [ "${arg:$i:1}" == "=" ]; then
          break
        fi
      done

      key="${arg:0:$i}"
      value="${arg:(( $i + 1 ))}"

      if [ "$key" = "name" ]; then
        name="$value"
      fi

      if [ "$key" == "version" ]; then
        version="$value"
      fi

      if [ "$key" == "debug" ]; then
        debug="$value"
      fi
    fi
  done

  if [ -z "$name" ] || [ -z "$version" ]; then
    # shellcheck disable=SC2155
    local error="$(encode_uri_component "Missing 'name/version' in arguments")"
    printf "ipc://stdout?value=%s\n" "$error"
    return 1
  fi
}

function encode_uri_component () {
  local string="$1"
  local length=${#string}
  local char=""
  local i

  for (( i = 0 ; i < length ; i++ )); do
    char=${string:$i:1}

    case "$char" in
      "-" | "_" | "." | "!" | "~" | "*" | "'" | "(" | ")") echo -ne "$char" ;;
      [a-zA-Z0-9]) echo -ne "$char" ;;
      *) printf '%%%02x' "'$char" ;;
    esac
  done
}

function decode_uri_component () {
  ## 'echo -e' is used so backslash escapes are interpreted
  echo -e "$(echo "$@" | sed -E 's/%([0-9a-fA-F]{2})/\\x\1/g;s/\+/ /g')"
}

function ipc_read () {
  local command="$1"
  local seq="$2"
  debug "Waiting for $command command and sequence ${seq:-none}"

  while read -r data; do
    debug "$data"

    if [ -z "$command" ] || [[ "$data"  =~ "ipc://$command" ]]; then
      if [ -z "$seq" ] || [[ "$data" =~ "seq=$seq"\&? ]]; then
        decode_uri_component "$(
          echo -e "$data"   | ## echo unescaped data
          grep -o '?.*'     | ## grep query string part of URI
          tr -d '?'         | ## remove '?'
          tr '&' '\n'       | ## transform '&' into newlines
          grep 'value='     | ## grep line with leading 'value='
          sed 's/value=//g'   ## remove 'value=' so actual value is left over
        )"

        return 0
      fi
    fi

    ## rebuffer
    echo -e "$data" > stdin
  done < stdin
  return 1
}

function ipc_write () {
  local command="$1"
  # shellcheck disable=SC2155
  local seq=0

  if [ "$command" != "stdout" ]; then
    seq="$(next_sequence)"
  fi

  {
    printf "ipc://%s?" "$1"
    shift

    if (( seq != 0 )); then
      printf "seq=%d&" "$seq"
    fi

    while (( $# > 0 )); do
      local arg="$1"
      local i=0
      shift

      for (( i = 0; i < ${#arg}; i++ )); do
        if [ "${arg:$i:1}" == "=" ]; then
          break
        fi
      done

      local key="${arg:0:$i}"
      local value="${arg:(( $i + 1))}"

      ## encode `key=value` pair
      echo -ne "$key=$(encode_uri_component "$(echo -ne "$value")")" 2>/dev/null

      if (( $# > 0 )); then
        printf '&'
      fi
    done

    ## flush with newline
    echo
  } | {
    while read -r line; do
      if [ "$command" != "stdout" ]; then
        debug "$line"
      fi

      echo -e "$line"
    done
  } > stdout & pids+=($!)

  echo "$seq"
  return "$seq"
}

function init_io () {
  local pipes=(stdin stdout)
  rm -f "${pipes[@]}" && mkfifo "${pipes[@]}"
}

function poll_io () {
  while true; do
    tee
  done < stdout & pids+=($!)

  while true; do
    # `tee -a` appends to the file
    tee -a stdin >/dev/null
  done
}

function onsignal () {
  kill -9 "${pids[@]}" 2>/dev/null
  exit 0
}

function init_signals () {
  trap "onsignal" SIGTERM SIGINT
}

# shellcheck disable=SC2120
function show_window () {
  ## show window by index (default 0)
  ipc_read resolve "$(ipc_write show index="${1:-0}")"
  return 0
}

function hide_window () {
  ## hide window by index (default 0)
  ipc_read resolve "$(ipc_write hide index="${1:-0}")"
  return 0
}

function navigate_window () {
  ## navigate window to URL by index (default 0)
  ipc_read resolve "$(ipc_write navigate index="${2:-0}" value="$1")"
  return 0
}

function send () {
  ## send data to window by index (default 0)
  ipc_write send event="$1" value="$2" index="${3:-0}" >/dev/null
  return 0
}

function send_data () {
  ## `base64 -w 0` will disable line wrapping
  send 'data' "$(echo -e "$@" | base64 -w 0)"
}

function set_size () {
  ## set size of window  by index (default 0)
  ipc_read resolve "$(ipc_write size index="${3:-0}" width="$1" height="$2")"
}

function get_config () {
  ## get config
  ipc_read resolve "$(ipc_write getConfig index=0)"
  return 0
}

function log () {
  ## write variadic values to stdout
  ipc_write stdout index=0 value="$*" >/dev/null
  return 0
}

function info () {
  log "\e[34m info$(echo -en "\e[0m") (${FUNCNAME[1]})> $*"
}

function warn () {
  log "\e[33m warn$(echo -en "\e[0m") (${FUNCNAME[1]})> $*"
}

function debug () {
  if (( debug == 1 )); then
    log "\e[32mdebug$(echo -en "\e[0m") (${FUNCNAME[1]})> $*"
  fi
}

function error () {
  log "\e[31merror$(echo -en "\e[0m") (${FUNCNAME[1]})> $*"
}

function panic () {
  log "\e[31mpanic$(echo -en "\e[0m") (${FUNCNAME[1]})> $*"
  exit 1
}

function wait_for_ready_event () {
  local READY_EVENT='{"event":"ready"}'
  warn "Waiting for ready event from front-end"
  while [ "$(ipc_read)" != "$READY_EVENT" ]; do
    :
  done
}

function start_application () {
  info "Starting Application ($name@$version)"
  info "Program Arguments: $*"

  show_window || panic "Failed to show window"
  navigate_window "file://$PWD/index.html" || panic "Failed to navigate to 'index.html'"

  while wait_for_ready_event; do
    warn "Setting 720x360 window size"
    set_size 720 360

    while true; do
      ## We format for 100 columns wide in batch mode (-b) with 1 iterations (-n)
      ## piped to head for the first 16 rows of standard output
      send_data "$(COLUMNS=100 top -n 1 -b | head -n 16)"
    done
  done
}

function main () {
  parse_command_line_arguments "$@" || return $?
  init_sequence || return $?
  init_signals || return $?
  init_io || return $?

  start_application "$@" & pids+=($!)

  poll_io || return $?
}

main "$@" || exit $?
