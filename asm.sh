#!/bin/sh

nasm  -Werror -f bin -l bios.lst -o Sources/FakePC/Resources/bios.bin Sources/FakePC/bios/bios.asm
