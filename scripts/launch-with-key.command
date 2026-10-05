#!/bin/zsh
# Saves an OpenAI API key into Scrbbl AI on the booted iPad simulator (Debug builds only).
while true; do
  echo "Scrbbl AI: paste your OpenAI API key ONCE, then press Return."
  echo "(Nothing will show while you paste; that's normal.)"
  read -s "KEY?Key: "
  echo
  KEY="${KEY//[[:space:]]/}"
  if [[ -z "$KEY" ]]; then
    echo "No key entered. Try again."
  elif [[ "$KEY" != sk-* ]]; then
    echo "That doesn't look like an OpenAI key (should start with sk-). Try again."
  elif (( $(print -r -- "$KEY" | grep -o "sk-" | wc -l) > 1 )); then
    echo "It looks like the key was pasted more than once. Try again, pasting just once."
  else
    break
  fi
  echo
done
echo "Got a key of ${#KEY} characters ending in ...${KEY[-4,-1]}."
SIMCTL_CHILD_OPENAI_API_KEY="$KEY" xcrun simctl launch --terminate-running-process booted ai.scrbbl.app >/dev/null \
  && echo "Done. The key is saved in the app. You can close this window." \
  || echo "Could not start the app. Tell Claude what this window says."
unset KEY
