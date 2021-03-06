//
//  main.swift
//  FakePC
//
//  Created by Simon Evans on 02/01/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
//  Initial entry point and argument parsing.
//

import Logging
import ArgumentParser
import Foundation
import FakePCLib


// Make the Logger.Level usable as @Option
extension Logger.Level: ExpressibleByArgument {
    public init?(argument: String) {
        for logLevel in Logger.Level.allCases {
            if argument == logLevel.defaultValueDescription {
                self = logLevel
                return
            }
        }
        return nil
    }

    public static var allValueStrings: [String] {
        Logger.Level.allCases.map { $0.defaultValueDescription }
    }
}


struct FakePCCommand: ParsableCommand {
    @Option(help: "Path to bios binary file or 'default', 'seabios'")
    var bios: String?

    @Flag(help: "Use an MDA/Curses display")
    var textMode = false

    @Option(help: "Path to image file for fd0 (A:)")
    var fd0: String?

    @Option(help: "Path to image file for fd1 (B:)")
    var fd1: String?

    @Option(help: "Path to image file for hd0 (C:)")
    var hd0: String?

    @Option(help: "Path to image file for hd1 (D:)")
    var hd1: String?

    @Option(help: "Path to image file for hd1 (E:)")
    var hd2: String?

    @Option(help: "Path to image file for hd1 (F:)")
    var hd3: String?

    @Option(help: "Path to image file for CD-ROM")
    var cdrom: String?

    @Option(help: "Boot order: a: floppy c: hard disk d: cdrom")
    var boot = "d,c,a"

    @Option(help: "Loglevel \(Logger.Level.allValueStrings.joined(separator: ", "))")
    var logLevel: Logger.Level = .error


    func run() {
        let biosURL: URL

        let _bios = bios ?? "default"
        switch _bios {
            case "default": biosURL = bundledBios("bios")
            case "seabios": biosURL = bundledBios("seabios")
            default: biosURL = URL(fileURLWithPath: _bios, isDirectory: false)
        }

        let fd0Disk = fd0 == nil ? nil : FDC.parseCommandLineArguments(fd0!)
        let fd1Disk = fd1 == nil ? nil : FDC.parseCommandLineArguments(fd1!)
        var hd0Disk = hd0 == nil ? nil : HDC.parseCommandLineArguments(hd0!)
        var hd1Disk = hd1 == nil ? nil : HDC.parseCommandLineArguments(hd1!)
        var hd2Disk = hd2 == nil ? nil : HDC.parseCommandLineArguments(hd2!)
        var hd3Disk = hd3 == nil ? nil : HDC.parseCommandLineArguments(hd3!)

        if cdrom != nil {
            let cdromDrive = HDC.parseCommandLineArgumentsFor(cdrom: cdrom!)
            if hd0Disk == nil { hd0Disk = cdromDrive }
            else if hd1Disk == nil { hd1Disk = cdromDrive }
            else if hd2Disk == nil { hd2Disk = cdromDrive }
            else if hd3Disk == nil { hd3Disk = cdromDrive }
            else {
                fatalError("Too many drives, the number of Hard disks and cdroms cannot exceed 4")
            }
        }

        var bootOrder: [Character] = []
        for part in boot.split(separator: ",").map(String.init) {
            let disk = part.lowercased()
            switch disk {
                case "a", "c", "d":
                    let ch = disk.first!
                    if bootOrder.contains(ch) {
                        fatalError("Boot Order specifies '\(disk)' multiple times")
                    }
                    bootOrder.append(ch)

                default: fatalError("Unknown boot order '\(disk)'")
            }
        }
        guard !bootOrder.isEmpty else { fatalError("No boot order specified") }

        let config = MachineConfig(biosURL: biosURL,
                                   textMode: textMode,
                                   fd0: fd0Disk,
                                   fd1: fd1Disk,
                                   hd0: hd0Disk,
                                   hd1: hd1Disk,
                                   hd2: hd2Disk,
                                   hd3: hd3Disk,
                                   bootOrder: bootOrder
        )

        do {
            let fakePC = try FakePC(config: config, logLevel: logLevel)
            if config.textMode {
                cursesStartupWith(fakePC)
            } else {
                startupWith(fakePC)
            }
        } catch {
            fatalError("Cant create the Fake PC: \(error)")
        }
    }
}

FakePCCommand.main()
