//
//  ResourceManager.swift
//  FakePC
//
//  Created by Simon Evans on 30/04/2020.
//
//  ResourceManager owns the IOPorts and IRQs and ensures that multiple devices
//  cannot reserve the same IOPort or IRQ ranges.
//

import HypervisorKit


final class ResourceManager {

    enum ResourceManagerError: Error {
        case ioPortInUse
        case irqInUse
        case invalidPort
        case invalidIrq
        case resourceUnavailable
    }

    // Drivers can register ownership of IO ports to handle IN,OUT
    // instructions.
    private let portRange: ClosedRange<IOPort>
    private let irqRange: ClosedRange<Int>
    private unowned let parent: ResourceManager?

    private var childResourceManagers: [ResourceManager] = []
    // Only root node has valid ranges, child nodes have them left as nil to catch accidental usage.
    private var ioPortHandlers: [IOPort: ISAIOHardware]!


    init(portRange: ClosedRange<IOPort>, irqRange: ClosedRange<Int>, parent: ResourceManager? = nil) {
        self.portRange = portRange
        self.irqRange = irqRange
        self.parent = parent
        if parent == nil {
            ioPortHandlers = [:]
        } else {
            ioPortHandlers = nil
        }
    }


    func reserve(portRange: ClosedRange<IOPort>, irqRange: ClosedRange<Int>) throws -> ResourceManager {
        for manager in childResourceManagers {
            if manager.portRange.overlaps(portRange) { throw ResourceManagerError.resourceUnavailable }
            if manager.irqRange.overlaps(irqRange) { throw ResourceManagerError.resourceUnavailable }
        }
        return ResourceManager(portRange: portRange, irqRange: irqRange, parent: self)
    }


    func registerIOPort(port: IOPort, _ hardware: ISAIOHardware) throws {
        try registerIOPort(ports: port...port, hardware)
    }


    func registerIOPort(ports: ClosedRange<IOPort>, _ hardware: ISAIOHardware) throws {
        if let parent = parent {
            try parent.registerIOPort(ports: ports, hardware)
        } else {
            for port in ports {
                guard portRange.contains(port) else { throw ResourceManagerError.invalidPort }
                guard ioPortHandlers[port] == nil else { throw ResourceManagerError.ioPortInUse }
            }
            for port in ports {
                ioPortHandlers[port] = hardware
            }
        }
    }

    func ioOut(port: IOPort, dataWrite: VMExit.DataWrite) throws {
        logger.trace("IO-OUT: \(String(port, radix: 16)): \(dataWrite)")
        if let hardware = ioPortHandlers[port] {
            try hardware.ioOut(port: port, operation: dataWrite)
        } else {
            logger.debug("IO-OUT: No handler for port \(String(port, radix: 16))")
        }
    }


    func ioIn(port: IOPort, dataRead: VMExit.DataRead) -> VMExit.DataWrite {
        logger.trace("IO-IN: \(String(port, radix: 16)): \(dataRead)")
        if let hardware = ioPortHandlers[port] {
            return hardware.ioIn(port: port, operation: dataRead)
        } else {
            logger.debug("IO-IN: No handler for port \(String(port, radix: 16))")
            return VMExit.DataWrite(bitWidth: dataRead.bitWidth, value: UInt64.max)!
        }
    }
}
