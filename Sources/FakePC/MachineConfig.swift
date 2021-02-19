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


struct MachineConfig {
    let biosURL: URL
    let textMode: Bool

    let fd0: Disk?
    let fd1: Disk?
    let hd0: Disk?
    let hd1: Disk?
    let hd2: Disk?
    let hd3: Disk?
}


