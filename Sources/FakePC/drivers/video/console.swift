//
//  console.swift
//  FakePC
//
//  Created by Simon Evans on 24/04/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
//  Protocol to describe a Console: a screen, keyboard + optional mouse.
//

protocol Console {
    var keyboard: PS2Device? { get }
    var mouse: PS2Device? { get }

    var updateHandler: (() -> ())? { get set }

    func setWindow(screenMode: ScreenMode)
    func updateDisplay()

    // Returns a charcter/attribute if there is a new character a the requested cordinates
    func rasteriseTextMemory(screenMode: ScreenMode, font: Font, newCharacter: (Int, Int) -> (character: UInt8, attribute: UInt8)?)

    // Debug Output. The console can decide whether to send this to stdout, stderr or its
    // own window or a logfile etc.
    func debugLog(_ entry: String)
}


extension Console {
    func debugLog(_ entry: String) {
        print("DEBUG:", entry)
    }
}
