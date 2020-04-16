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

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let console = Console()
        ISA.setConsole(console)

        runVMThread()
    }


    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
}


func startup() {
    autoreleasepool {
        var psn = ProcessSerialNumber( highLongOfPSN: 0, lowLongOfPSN: UInt32(kCurrentProcess))
        TransformProcessType(&psn, UInt32(kProcessTransformToForegroundApplication))
        _ = FakePCApplication.shared
        let fakePCAppController = FakePCAppController()
        NSApp.delegate = fakePCAppController
        NSApp.run()
    }
}

#endif
