#!/bin/bash

for fn in $(find "artifacts/contracts" -type f | grep -v "\.dbg\." | sort )
do
	#[[ $fn = */Test* ]] && continue
	#[[ $fn = */I* ]] && continue
	[[ $fn = artifacts/contracts/interfaces/* ]] && continue
	[[ $fn = artifacts/contracts/test/* ]] && continue
	[[ $fn = artifacts/contracts/libraries/* ]] && continue
    bytecode=$(cat ${fn} | jq .deployedBytecode | awk -F "\"" '{print $2}')
	[[ $bytecode = 0x ]] && continue
    let size=${#bytecode}/2
    name="$(basename $fn)"

    printf "%-40s%6s\n" "${name}~" "~${size}" | tr ' ~' '- '
done
