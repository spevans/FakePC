#!/bin/bash

./asm.sh
if [ "$1" == "--clean" ];   then
   echo swift package clean
fi
swift build
