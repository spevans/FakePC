//
//  cocoa-console.swift
//  FakePC
//
//  Created by Simon Evans on 16/04/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
//  Cocoa specific startup and NSApplication.
//

#if os(macOS)

import Cocoa


class FakePCApplication: NSApplication {

}


class FakePCAppController: NSObject, NSApplicationDelegate {

    private let fakePC: FakePC


    init(fakePC: FakePC) {
        self.fakePC = fakePC
        super.init()
    }


    func applicationDidFinishLaunching(_ aNotification: Notification) {
        fakePC.runVMThread()
    }


    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
}


func startupWith(_ fakePC: FakePC) {
    autoreleasepool {
        var psn = ProcessSerialNumber( highLongOfPSN: 0, lowLongOfPSN: UInt32(kCurrentProcess))
        TransformProcessType(&psn, UInt32(kProcessTransformToForegroundApplication))
        _ = FakePCApplication.shared
        let fakePCAppController = FakePCAppController(fakePC: fakePC)
        NSApp.delegate = fakePCAppController
        NSApp.run()
    }
}

#endif
