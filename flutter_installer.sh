#!/bin/bash

echo "Installing Flutter SDK..."

git clone https://github.com/flutter/flutter.git -b stable

# No PATH export needed
./flutter/bin/flutter doctor -v
