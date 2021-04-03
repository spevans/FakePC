//
//  CursesConsole.swift
//  FakePC
//
//  Created by Simon Evans on 24/04/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
//  Text (MDA) console using curses text mode, screen + keyboard, no mouse.
//


#if canImport(LinuxCurses)
import LinuxCurses
import Glibc
#endif

#if canImport(DarwinCurses)
import DarwinCurses
import Darwin
#endif

import CFakePC


public func cursesStartupWith(_ fakePC: FakePC) {
    let kb = fakePC.isa.console.keyboard as! CursesKeyboard
    fakePC.runVMThread()
    kb.keyboardLoop()
    endwin()
}


final class CursesConsole: Console {
    let keyboard: PS2Device?
    let mouse: PS2Device? = nil

    var updateHandler: (() -> ())?

    init() {
        setlocale(LC_ALL, "")
        initscr()
        cbreak()
        noecho()
        nonl()
        halfdelay(2)
        intrflush(stdscr, false)
        keypad(stdscr, true)
        keyboard = CursesKeyboard()
    }


    func setWindow(screenMode: ScreenMode) {
    }


    func updateDisplay() {
        if let handler = updateHandler {
            handler()
        }
    }


    func rasteriseTextMemory(screenMode: ScreenMode, font: Font,
                             newCharacter: (_ row: Int, _ column: Int) -> (character: UInt8, attribute: UInt8)?) {
        for row in 0..<screenMode.textRows {
            for column in 0..<screenMode.textColumns {
                if let (character, _) = newCharacter(row, column) {
                    writeCharAtRowColumn(Int32(row), Int32(column), character)
                }
            }
        }
        refresh()
    }
}
