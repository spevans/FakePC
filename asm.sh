#!/bin/sh

nasm  -Werror -f bin -l bios.lst -o Sources/FakePCLib/Resources/bios.bin Sources/FakePCLib/bios/bios.asm
