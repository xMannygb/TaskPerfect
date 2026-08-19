#!/usr/bin/env bash
#
# Connectivity probe for the Intermedia Hosted Exchange mailbox over EWS.
#
#   ./verify.sh peter@lastmile.net
#   ./verify.sh peter@lastmile.net --host east.exch092.serverdata.net
#   ./verify.sh 'EXCH092\peter' --auth ntlm   # only if the bare address fails
#
# NOT a gate. Whether EWS is enabled is already settled three ways — see
# ../BEFORE-EWS.md. This is here for the narrower job of proving that a
# particular machine, on a particular network, can reach the endpoint and get a
# 200 back. Useful on a new build machine, or when something that worked stops.
#
# Auth defaults to --anyauth, matching what the app does: Task Task exposes no
# auth-mode picker and reaches this mailbox on the bare e-mail address with an
# empty domain, so the SOAP layer negotiates rather than hardcoding NTLM.
#
# The password is read from the terminal and handed to curl through a config file
# on stdin, never on the command line — argv is world-readable via `ps` on a
# shared machine.

set -euo pipefail

HOST="east.exch092.serverdata.net"
AUTH="anyauth"
USER_NAME=""

while [ $# -gt 0 ]; do
  case "$1" in
    --host)  HOST="${2:-}";  shift 2 ;;
    --auth)  AUTH="${2:-}";  shift 2 ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    -*)
      echo "unknown option: $1" >&2; exit 2 ;;
    *)
      USER_NAME="$1"; shift ;;
  esac
done

if [ -z "$USER_NAME" ]; then
  echo "usage: ./verify.sh <username> [--host HOST] [--auth anyauth|ntlm|basic]" >&2
  echo "       username is normally the full e-mail address, no domain prefix." >&2
  exit 1
fi

case "$AUTH" in
  anyauth) AUTH_FLAG="--anyauth" ;;
  ntlm)    AUTH_FLAG="--ntlm" ;;
  basic)   AUTH_FLAG="--basic" ;;
  *) echo "--auth must be anyauth, ntlm or basic" >&2; exit 2 ;;
esac

ENDPOINT="https://${HOST}/EWS/Exchange.asmx"
BODY="$(dirname "$0")/getfolder.xml"

if [ ! -f "$BODY" ]; then
  echo "missing $BODY" >&2
  exit 1
fi

read -r -s -p "Password for ${USER_NAME}: " PASSWORD
echo
echo

RESPONSE="$(mktemp -t ews-response.XXXXXX)"
cleanup() { rm -f "$RESPONSE"; unset PASSWORD; }
trap cleanup EXIT

echo "→ POST ${ENDPOINT}  (auth: ${AUTH})"
echo

# Credentials go in via --config on stdin so they never appear in argv.
HTTP_CODE=$(
  printf 'user = "%s:%s"\n' "$USER_NAME" "$PASSWORD" |
  curl -s -o "$RESPONSE" -w '%{http_code}' \
    --config - \
    --max-time 30 \
    "$AUTH_FLAG" \
    -H "Content-Type: text/xml; charset=utf-8" \
    -H 'SOAPAction: "http://schemas.microsoft.com/exchange/services/2006/messages/GetFolder"' \
    --data-binary @"$BODY" \
    "$ENDPOINT"
) || true

echo "HTTP ${HTTP_CODE}"
echo

case "${HTTP_CODE}" in
  200)
    if grep -q 'ResponseClass="Success"' "$RESPONSE"; then
      echo "EWS reachable from this machine. Tasks folder:"
      grep -o '<t:DisplayName>[^<]*</t:DisplayName>' "$RESPONSE" || true
      grep -o '<t:TotalCount>[^<]*</t:TotalCount>' "$RESPONSE" || true
      echo
      echo "Worth keeping: this response is real XML from this mailbox, and beats"
      echo "Microsoft's documentation when writing EWSMapper. Save it somewhere."
    else
      echo "200 OK, but not a success response. Body:"
      cat "$RESPONSE"
    fi
    ;;
  401)
    echo "401 Unauthorized — credentials rejected, or no mutually agreeable scheme."
    echo
    echo "Try, in this order:"
    echo "  1. the full e-mail address with no domain prefix (this is what works"
    echo "     in practice — see ../BEFORE-EWS.md)"
    echo "  2. --auth ntlm, then --auth basic, to see which the server offers"
    echo "  3. DOMAIN\\user form:  ./verify.sh 'EXCH092\\peter' --auth ntlm"
    ;;
  403)
    echo "403 Forbidden. Normally this means EWS is off for the mailbox plan —"
    echo "but Intermedia has confirmed it is on for this one, and a third-party"
    echo "client syncs it over this exact path. So suspect this machine's egress"
    echo "first: a proxy, a TLS-inspecting firewall, or a blocked user agent."
    ;;
  000)
    echo "No response from ${HOST}. DNS, network, or the 30s timeout."
    ;;
  *)
    echo "Unexpected response. Body:"
    cat "$RESPONSE"
    ;;
esac
