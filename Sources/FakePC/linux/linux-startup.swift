//
//  linux-startup.swift
//  FakePC
//
//  Created by Simon Evans on 16/04/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
//  Linux specific startup routines.
//

#if os(Linux)


func startup() {
    let console = SDLConsole()
    ISA.setConsole(console)

    runVMThread()
}

#endif
