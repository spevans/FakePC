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


public func startupWith(_ fakePC: FakePC) {
    fakePC.runVMThread()
}

#endif
