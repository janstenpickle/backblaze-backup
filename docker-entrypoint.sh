#!/bin/sh
set -e 

if [ -n "$TIMEZONE" ]; then
  echo ${TIMEZONE} > /etc/timezone && \
  dpkg-reconfigure -f noninteractive tzdata
fi

if [ -z "$SCHEDULE" ]; then
  echo Missing SCHEDULE environment variable 2>&1
  echo Example -e SCHEDULE=\"\*/10 \* \* \* \* \*\" 2>&1
  exit 1
fi
if [ -z "$BUCKET" ]; then
  echo Missing BUCKET environment variable, this is needed to upload files 2>&1
  exit 1
fi
if [ -z "$GPG_PASSPHRASE" ]; then
  echo Missing GPG_PASSPHRASE environment variable, this is needed to encrypt/decrypt files 2>&1
  exit 1
fi

EXIT_CODE=1
AUTH_FAILED=1
RETRY=0
if [ -n "$B2_ACCOUNT_ID" ] && [ -n "$B2_APPLICATION_KEY" ]; then
  while [ $AUTH_FAILED -ne 0 ] && [ $RETRY -lt $AUTHORIZATION_FAIL_MAX_RETRIES ]; do
    # Exclude on first run only if /root/.b2_account_info exists
    if [ $RETRY -gt 0 ] || [ ! -f /root/.b2_account_info ]; then
      b2 authorize_account "$B2_ACCOUNT_ID" "$B2_APPLICATION_KEY"
    fi
    OUTPUT=`$@`
    if [ "$OUTPUT" != *"bad_auth_token"* ] && [ "$OUTPUT" != *"expired_auth_token"* ]; then
      AUTH_FAILED=0
    fi
    EXIT_CODE=$?
    RETRY=$((RETRY+1))
  done
else
  echo Missing B2_ACCOUNT_ID or B2_APPLICATION_KEY environment variables, these are needed to upload files 2>&1
  exit 1
fi
if [ "x1" = "x${EXIT_CODE}" ]; then
  echo $OUTPUT 2>&1
  exit 1
fi
exec go-cron -s "${SCHEDULE}" -- /usr/local/sbin/backup-run
