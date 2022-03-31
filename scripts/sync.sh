#!/bin/bash

tags() {
  repo=$1
  gh api repos/$repo/releases --paginate | jq -r '.[].tag_name'
}


my_tags=$(tags burrito-elixir/beam-machine-darwin)
otp_tags=$(
  tags erlang/otp | \
    # OTP 23.3+, or 24
    grep -e OTP-23.3 -e OTP-24
)

for i in $otp_tags; do
  if [[ "$my_tags" == *"$i"* ]]; then
    echo release $i already exists
  else
    echo "Kicking off build for $i"
    gh workflow run -R "burrito-elixir/beam-machine-darwin" erlang-build.yml -f erlang_version=${i/OTP-/}
  fi
done
