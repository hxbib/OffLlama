#!/bin/bash
cd /workspace/kickoff/seg
idle=0
while true; do
  pl=$(curl -s -f "<REDACTED_SIGNED_STREAM_URL>")
  if [ -z "$pl" ]; then idle=$((idle+1)); echo "$(date +%T) playlist fail $idle"; [ $idle -gt 60 ] && break; sleep 10; continue; fi
  echo "$pl" | grep -q ENDLIST && { echo "$(date +%T) ENDLIST"; end=1; }
  new=0
  for s in $(echo "$pl" | grep -o 'segment_[0-9]*' | cut -d_ -f2); do f=$(printf "seg_%05d.ts" $s); [ -s $f ] && continue; curl -s -f -o $f "<REDACTED_SIGNED_STREAM_URL>" && new=1 || rm -f $f; done
  [ "$end" = 1 ] && break
  if [ $new = 0 ]; then idle=$((idle+1)); else idle=0; fi
  [ $idle -gt 60 ] && { echo "$(date +%T) no new segs, stop"; break; }
  sleep 6
done
echo "$(date +%T) follow exit"
