#!/bin/bash
cd /workspace/kickoff/seg
for s in $(seq 155 960); do f=$(printf "seg_%05d.ts" $s); [ -s $f ] && continue; curl -s -f -o $f "<REDACTED_SIGNED_STREAM_URL>" || { rm -f $f; echo miss $s; }; done
echo done
