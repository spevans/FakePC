//
//  linux-console.swift
//  FakePC
//
//  Created by Simon Evans on 16/04/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
//  Cocoa interface between the system and the host OS screen, keyboard and mouse.
//

#if os(Linux)

// Dummy interface for Linux (for now). Will probably use SDL for the screen eventually.

class SDLConsole: Console {
    let keyboard: PS2Device? = nil
    let mouse: PS2Device? = nil

    var updateHandler: (() -> ())?


    init() {
    }


    func setWindow(screenMode: ScreenMode) {
    }


    func updateDisplay() {
    }


    func rasteriseTextMemory(screenMode: ScreenMode, font: Font, newCharacter: (Int, Int) -> (character: UInt8, attribute: UInt8)?) {
    }
}

#endif
