#!/usr/bin/env bash

declare name=""
declare version=""

while (( $# > 0 )); do
	arg="$1"
	shift

	if [ "${arg:0:2}" == "--" ]; then
		arg="${arg:2}"

		for (( i = 0; i < ${#arg}; ++i )); do
			## look for '='
			if [ "${arg:$i:1}" == "=" ]; then
				break
			fi
		done

		key="${arg:0:$i}"
		value="${arg:(( $i + 1 ))}"

		if [ "$key" == "name" ]; then
			name="$value"
		fi

		if [ "$key" == "version" ]; then
			version="$value"
		fi
	fi
done

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

echo "ipc://show"
echo "ipc://navigate?value=file://$PWD/index.html"
echo "ipc://stdout?value=Starting%20application"

## '=' is encoded as '%3D'
echo "ipc://stdout?value=name+%3D+$name"
echo "ipc://stdout?value=version+%3D+$version"
