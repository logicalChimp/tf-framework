#!/bin/bash
if [ $# -lt 1 ]; then
  echo "Usage: contents <filepath> [<password>]"
  exit 1
fi
if [ $# -gt 2 ]; then
  echo "Usage: contents <filepath> [<password>]"
  exit 1
fi

echo File: $1
if [ -f $1 ]; then 
  if [ $# -eq 1 ]; then 
    echo $1
  else
    SCRATCH_FILE=$(mktemp -t tmp.xxxxxxxxxx)
    function cleanup {
        rm -rf ${SCRATCH_FILE}
    }
    trap finish EXIT

    echo $2 > $SCRATCH_FILE
    export ANSIBLE_VAULT_PASSWORD_FILE=${SCRATCH_FILE}
    ansible-vault view $1 2>/dev/null
    [[ $? == 0 ]] && exit 0 || exit 1
  fi
  exit 0;
fi


