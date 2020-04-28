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

    private let config: MachineConfig


    init(config: MachineConfig) {
        self.config = config
        super.init()
    }


    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let console = CocoaConsole()
        ISA.setConsole(console)

        runVMThreadWith(config: config)
    }


    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
}


func startupWith(config: MachineConfig) {
    autoreleasepool {
        var psn = ProcessSerialNumber( highLongOfPSN: 0, lowLongOfPSN: UInt32(kCurrentProcess))
        TransformProcessType(&psn, UInt32(kProcessTransformToForegroundApplication))
        _ = FakePCApplication.shared
        let fakePCAppController = FakePCAppController(config: config)
        NSApp.delegate = fakePCAppController
        NSApp.run()
    }
}

#endif
