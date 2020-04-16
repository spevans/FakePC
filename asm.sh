#!/bin/sh

nasm  -Werror -f bin -l bios.lst -o bios.bin Sources/FakePC/bios/bios.asm
