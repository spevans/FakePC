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
    private(set) var textMode: Bool = false

    private(set) var fd0: Disk? = nil
    private(set) var fd1: Disk? = nil

    private(set) var hd0: Disk? = nil
    private(set) var hd1: Disk? = nil

    init<C: Collection>(_ arguments: C) where C.Element == String {
        var _biosURL: URL?
        for argument in arguments {
            if argument == "--text" {
                textMode = true
                continue
            }

            let parameters = argument.split(maxSplits: 1, omittingEmptySubsequences: false, whereSeparator: { $0 == "=" }).map { String($0) }
            if parameters.count == 2, parameters.last != "" {

                switch String(parameters[0]) {
                    case "--bios": _biosURL = URL(fileURLWithPath: parameters[1], isDirectory: false)
                    case "--fd0": fd0 = FDC.parseCommandLineArguments(parameters[1])
                    case "--fd1": fd1 = FDC.parseCommandLineArguments(parameters[1])
                    case "--hd0": hd0 = HDC.parseCommandLineArguments(parameters[1])
                    case "--hd1": hd1 = HDC.parseCommandLineArguments(parameters[1])
                    case "--cdrom": hd1 = HDC.parseCommandLineArgumentsFor(cdrom: parameters[1])
                    default: fatalError("Unknown option: \(parameters[0])")

                }
            } else {
                fatalError("Unknown argument: \(argument)")
            }
        }
        if _biosURL == nil {
            fatalError("No bios specified")
        }
        biosURL = _biosURL!
    }
}
