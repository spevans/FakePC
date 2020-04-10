import Foundation
import HypervisorKit


private var ram: MemoryRegion?
private var hma: MemoryRegion?


func hexNum<T: BinaryInteger>(_ value: T, width: Int) -> String {
    let num = String(value, radix: 16)
    if num.count <= width {
        return String(repeating: "0", count: width - num.count) + num
    }
    return num
}


private var ioPortHandlers: [IOPort:ISAIOHardware] = [:]

func registerIOPort(ports: ClosedRange<IOPort>, _ hardware: ISAIOHardware) {
    for port in ports {
        ioPortHandlers[port] = hardware // (outFunction, inFunction)
    }
}

func ioOut(port: IOPort, dataWrite: VMExit.DataWrite) throws {
    print("IO-OUT: \(String(port, radix: 16)):", dataWrite)
    if let hardware = ioPortHandlers[port] {
        try hardware.ioOut(port: port, operation: dataWrite)
    }
}


func ioIn(port: IOPort, dataRead: VMExit.DataRead) -> VMExit.DataWrite {
    print("IO-IN: \(String(port, radix: 16)):", dataRead)
    if let hardware = ioPortHandlers[port] {
        return hardware.ioIn(port: port, operation: dataRead)
    } else {
        return VMExit.DataWrite(bitWidth: dataRead.bitWidth, value: 0)!
    }
}


func showRegisters(_ vcpu: VirtualMachine.VCPU) {
    func showReg(_ name: String, _ value: UInt16) {
        let w = hexNum(value, width: 4)
        print("\(name): \(w)", terminator: " ")
    }

    showReg("\nCS", vcpu.registers.cs.selector)
    showReg("SS", vcpu.registers.ss.selector)
    showReg("DS", vcpu.registers.ds.selector)
    showReg("ES", vcpu.registers.es.selector)
    showReg("FS", vcpu.registers.fs.selector)
    showReg("GS", vcpu.registers.gs.selector)
    print("FLAGS", vcpu.registers.rflags)
    showReg("IP", vcpu.registers.ip)
    showReg("AX", vcpu.registers.ax)
    showReg("BX", vcpu.registers.bx)
    showReg("CX", vcpu.registers.cx)
    showReg("DX", vcpu.registers.dx)
    showReg("DI", vcpu.registers.di)
    showReg("SI", vcpu.registers.si)
    showReg("BP", vcpu.registers.bp)
    showReg("SP", vcpu.registers.sp)
    print("")
}



func dumpMemory(_ memory: MemoryRegion, offset: Int, count: Int) {
    let ptr = memory.rawBuffer.baseAddress!.advanced(by: offset)
    let buffer = UnsafeRawBufferPointer(start: ptr, count: count)

    var idx = 0
    print("\(hexNum(offset + idx, width: 5)): ", terminator: "")
    for byte in buffer {
        print(hexNum(byte, width: 2), terminator: " ")
        idx += 1
        if idx == count { break }
        if idx.isMultiple(of: 16) {
            print("\n\(hexNum(offset + idx, width: 5)): ", terminator: "")
        }
    }
    print("\n")
}


func main() throws {
    #if os(Linux)
    let biosURL = URL(fileURLWithPath: "/home/spse/src/osx/FakePC/bios.bin", isDirectory: false)
    #else
    let biosURL = URL(fileURLWithPath: "/Users/spse/Files/src/osx/FakePC/bios.bin", isDirectory: false)
    #endif
    let biosImage = try Data(contentsOf: biosURL)

    let vm = try VirtualMachine()
    
    
    // Currently only KVM will emulate an PIC and PIT, HVF will not. The PIC/PIT code needs to be added into
    // HypervisorKit then it can be enabled there for HVF and the KVM one used on Linux.
    // try vm.addPICandPIT()

    ram = try vm.addMemory(at: 0, size: 0xA0000) // 640K RAM everything above is Video RAM and ROM
    hma = try vm.addMemory(at: 0x100000, size: 0x10000) // HMA 64KB ram at 1MB mark
    // Top 4K
    let biosRegion = try vm.addMemory(at: 0xFF000, size: 4096)

    try biosRegion.loadBinary(from: biosImage, atOffset: 0x0)
    let vcpu = try vm.createVCPU()
    vcpu.setupRealMode()
    registerPICHardware(vcpu: vcpu)

    var count = 0

    while count < 500000 {
        let vmExit = try vcpu.run()
        count += 1

        switch vmExit {
            case .ioOutOperation(let port, let data):
                if case VMExit.DataWrite.word(let value) = data {
                    let ip = UInt64(vcpu.registers.cs.base) + vcpu.registers.rip
                    // Is call from BIOS?
                    if (port >= 0xE0 && port <= 0xEF) && (ip >= 0xFF000 && ip <= 0xFFFFF) {
                        try biosCall(vm: vm, subSystem: port, function: value)
                        continue
                    } else {
                        print("Port: \(String(port, radix: 16)) IP: \(String(ip, radix: 16))")
                        print("Not a bios call")
                    }

            }
            try ioOut(port: port, dataWrite: data)

            case .ioInOperation(let port, let dataRead):
            let data = ioIn(port: port, dataRead: dataRead)
            print("ioIn(0x\(String(port, radix: 16)), \(dataRead) => \(data))")
            vcpu.setIn(data: data)

            case .memoryViolation:
                //print(vmExit)
                //print("Ignoring violation:", violation)
                continue

        case .exception(let exceptionInfo):
                showRegisters(vcpu)
                let offset = Int(vcpu.registers.cs.base) + Int(vcpu.registers.ip)
                dumpMemory(vm.memoryRegions[0], offset: offset, count: 16)

                fatalError("\(vmExit): \(exceptionInfo)")

            case .debug(let debug):
                showRegisters(vcpu)
                fatalError("\(vmExit): \(debug)")

            case .hlt:
                print("HLT... exiting")
                showRegisters(vcpu)
                return


            default:
                print(vmExit)
                showRegisters(vcpu)
                fatalError("Unhandled exit: \(vmExit)")
        }
        processHardware()
    }
}


try main()
