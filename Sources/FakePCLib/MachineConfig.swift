//
//  MachineConfig.swift
//  FakePC
//
//  Created by Simon Evans on 27/04/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
//  Description of the VM instance including attached hardware etc.
//

import Foundation


public struct MachineConfig {
    public let biosURL: URL
    public let textMode: Bool

    public let fd0: Disk?
    public let fd1: Disk?
    public let hd0: Disk?
    public let hd1: Disk?
    public let hd2: Disk?
    public let hd3: Disk?

    public init(biosURL: URL, textMode: Bool, fd0: Disk?, fd1: Disk?, hd0: Disk?, hd1: Disk?, hd2: Disk?, hd3: Disk?) {
        self.biosURL = biosURL
        self.textMode = textMode
        self.fd0 = fd0
        self.fd1 = fd1
        self.hd0 = hd0
        self.hd1 = hd1
        self.hd2 = hd2
        self.hd3 = hd3
    }
}


// Used to access a BIOS imaged stored in the Bundle.
public func bundledBios(_ name: String) -> URL {
    if let url = Bundle.module.url(forResource: name, withExtension: "bin") {
        return url
    } else {
        fatalError("Cant find \(name).bin in Bundle resources")
    }
}
