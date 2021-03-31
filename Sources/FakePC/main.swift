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


// The singleton object representing the PC
private(set) internal var fakePC: FakePC!

private(set) var logger: Logger = {
    LoggingSystem.bootstrap(StreamLogHandler.standardError)
    var logger = Logger(label: "FakePC")
    logger.logLevel = .error
    return logger
}()


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


    @Option(help: "Loglevel \(Logger.Level.allValueStrings.joined(separator: ", "))")
    var logLevel: Logger.Level = .error

    func bundledBios(_ name: String) -> URL {
        if let url = Bundle.module.url(forResource: name, withExtension: "bin") {
            return url
        } else {
            fatalError("Cant find \(name).bin in Bundle resources")
        }
    }

    func run() {
        logger.logLevel = logLevel
        let biosURL: URL

        let _bios = bios ?? "default"
        switch _bios {
            case "default": biosURL = bundledBios("bios")
            case "seabios": biosURL = bundledBios("seabios")
            default: biosURL = URL(fileURLWithPath: _bios, isDirectory: false)
        }

        let fd0Disk = fd0 == nil ? nil : FDC.parseCommandLineArguments(fd0!)
        let fd1Disk = fd1 == nil ? nil : FDC.parseCommandLineArguments(fd1!)
        let hd0Disk = hd0 == nil ? nil : HDC.parseCommandLineArguments(hd0!)
        let hd1Disk = hd0 == nil ? nil : HDC.parseCommandLineArguments(hd1!)
        let hd2Disk = hd0 == nil ? nil : HDC.parseCommandLineArguments(hd2!)
        let hd3Disk = hd0 == nil ? nil : HDC.parseCommandLineArguments(hd3!)

        let config = MachineConfig(biosURL: biosURL,
                                   textMode: textMode,
                                   fd0: fd0Disk,
                                   fd1: fd1Disk,
                                   hd0: hd0Disk,
                                   hd1: hd1Disk,
                                   hd2: hd2Disk,
                                   hd3: hd3Disk
        )
        logger.info("biosURL: \(biosURL)")
        logger.debug("Config: \(config)")

        do {
            fakePC = try FakePC(config: config)
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
