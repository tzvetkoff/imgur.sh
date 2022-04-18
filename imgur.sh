#!/bin/bash

#
# Usage
#

usage() {
  echo 'Usage:'
  echo "  ${0} [options] <images...>"
  echo
  echo 'Options:'
  echo '  -h, --help                                        Print this message'
  echo '  -v, --verbose                                     Verbose output'
  echo '  -a, --anonymous                                   Force anonymous posts'
  echo '  -A ACCESS_TOKEN, --access-token=ACCESS_TOKEN      Override access token'
  echo '  -p PRIVACY, --privacy=PRIVACY                     Set post privacy'
  echo '  -t TITLE, --title=TITLE                           Set post title'
  echo '  -d DESCRIPTION, --description=DESCRIPTION         Set post description'
  echo
  echo "To authorize imgur.sh to post on your behalf, please open the following URL in your browser:"
  echo "https://api.imgur.com/oauth2/authorize?client_id=${CLIENT_ID}&response_type=token"
  exit "${1}"
}

#
# Curl helper
#

do_curl() {
  ${VERBOSE} && echo "--------------------------------"
  ${VERBOSE} && echo ">> ${CURL[*]} ${*}"
  API_RESPONSE=$("${CURL[@]}" "${@}")
  CURL_EXIT_CODE=${?}
  ${VERBOSE} && echo "<< ${API_RESPONSE}"
  ${VERBOSE} && echo "--------------------------------"
  return ${CURL_EXIT_CODE}
}

#
# Upload helper
#

do_upload() {
  CURL_ARGS=()
  CURL_ARGS+=('-F' 'type=file')
  CURL_ARGS+=('-F' "image=@${1}"); shift
  CURL_ARGS+=('-F' "privacy=${1}"); shift
  CURL_ARGS+=('-F' "title=${1}"); shift
  CURL_ARGS+=('-F' "description=${1}"); shift
  CURL_ARGS+=('https://api.imgur.com/3/image.xml')

  do_curl "${CURL_ARGS[@]}"
  if [[ ${?} -ne 0 ]]; then
    echo "Error uploading ${1}" >&2
    echo >&2
    echo "${API_RESPONSE}" >&2
    exit 1
  fi
}

#
# Album helper
#

do_create_album() {
  CURL_ARGS=()
  CURL_ARGS+=('-F' "privacy=${1}"); shift
  CURL_ARGS+=('-F' "title=${1}"); shift
  CURL_ARGS+=('-F' "description=${1}"); shift
  while [[ -n "${1}" ]]; do
    CURL_ARGS+=('-F' "deletehashes[]=${1}"); shift
  done
  CURL_ARGS+=('https://api.imgur.com/3/album.xml')

  do_curl "${CURL_ARGS[@]}"
  if [[ ${?} -ne 0 ]]; then
    echo 'Error creating album' >&2
    echo >&2
    echo "${API_RESPONSE}" >&2
    exit 1
  fi
}

#
# Response parser
#

do_response() {
  VALUE="${API_RESPONSE}"
  VALUE="${VALUE##*<${1}>}"
  VALUE="${VALUE%%</${1}>*}"
  echo "${VALUE}"
}

#
# Default values
#

CLIENT_ID='2b3fd5528efd794'
ACCESS_TOKEN=''
TITLE=''
DESCRIPTION=''
PRIVACY=''
VERBOSE='false'

#
# User config
#

if [[ -f "${HOME}/.config/imgur.sh/config" ]]; then
  # shellcheck disable=SC1090
  source "${HOME}/.config/imgur.sh/config"
fi

#
# Parse arguments
#

PARSE='true'
ARGS=()
while [[ -n "${1}" ]]; do
  if ${PARSE}; then
    case "${1}" in
      -h|--help) usage 0;;
      -v|--verbose) VERBOSE='true';;
      -a|--anonymous) ACCESS_TOKEN='';;

      -A|--access-token) ACCESS_TOKEN="${2}"; shift;;
      --access-token=*)  ACCESS_TOKEN="${1:15}";;
      -A*)               ACCESS_TOKEN="${1:2}";;

      --save-config) mkdir -p "${HOME}/.config/imgur.sh"; : > "${HOME}/.config/imgur.sh/config"; echo "ACCESS_TOKEN=${ACCESS_TOKEN}" >> "${HOME}/.config/imgur.sh/config"; exit 0;;

      -p|--privacy) PRIVACY="${2}"; shift;;
      --privacy=*)  PRIVACY="${1:10}";;
      -p*)          PRIVACY="${1:2}";;

      -t|--title) TITLE="${2}"; shift;;
      --title=*)  TITLE="${1:8}";;
      -t*)        TITLE="${1:2}";;

      -d|--description) DESCRIPTION="${2}"; shift;;
      --description=*)  DESCRIPTION="${1:14}";;
      -d*)              DESCRIPTION="${1:2}";;

      --) PARSE=false;;
      -*) echo "${0}: invalid option: ${1}" >&2; echo >&2; usage 1 >&2;;
      *)  ARGS+=("${1}");;
    esac
  else
    ARGS+=("${1}")
  fi

  shift
done

set -- "${ARGS[@]}"

#
# Check positional arguments
#

if [[ ${#} -lt 1 ]]; then
  echo "${0}: wrong number of arguments (given ${#}, expected >= 1)" >&2
  echo >&2
  usage 1 >&2
fi

#
# Configure curl
#

CURL=('curl' '--silent')
if [[ -n "${ACCESS_TOKEN}" ]]; then
  CURL+=('-H' "Authorization: Bearer ${ACCESS_TOKEN}")
else
  CURL+=('-H' "Authorization: Client-ID ${CLIENT_ID}")
fi

#
# Do the Rambo!
#

if [[ ${#} -gt 1 ]]; then
  DELETE_HASHES=()
  while [[ -n "${1}" ]]; do
    do_upload "${1}" "${PRIVACY}"
    DELETE_HASH=$(do_response 'deletehash')
    DELETE_HASHES+=("${DELETE_HASH}")
    shift
  done

  do_create_album "${PRIVACY}" "${TITLE}" "${DESCRIPTION}" "${DELETE_HASHES[@]}"
  ID=$(do_response 'id')
  DELETE_HASH=$(do_response 'deletehash')

  echo "Post URL: https://imgur.com/a/${ID}"
  echo "Delete URL: https://imgur.com/delete/${DELETE_HASH}"
else
  do_upload "${1}" "${PRIVACY}" "${TITLE}" "${DESCRIPTION}"
  ID=$(do_response 'id')
  LINK=$(do_response 'link')
  DELETE_HASH=$(do_response 'deletehash')

  echo "Post URL: https://imgur.com/${ID}"
  echo "Image URL: ${LINK}"
  echo "Delete URL: https://imgur.com/delete/${DELETE_HASH}"
fi
