#!/bin/bash -e
IFS="/" read -ra parts <<< "$(pwd)"
len=${#parts[@]}
cpu=${parts[$len-1]}
erlang_version=${parts[$len-2]}
erlang_version=${erlang_version/#OTP-}

echo "CPU: $cpu"
echo "Version: $erlang_version"

elixir $(which mkerlang.exs) --otp-version=$erlang_version --os=darwin --arch=$cpu
touch BUILD_OK