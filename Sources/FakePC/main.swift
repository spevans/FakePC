import Foundation
import HypervisorKit

private var ram: MemoryRegion?
private var hma: MemoryRegion?


func debugLog(_ arguments: Any..., separator: String = " ") {
    var entry = ""

    var sep = ""
    for arg in arguments {
        entry += "\(arg)"
        entry += sep
        sep = separator
    }

    if let console = ISA.console {
        console.debugLog(entry)
    } else {
        print(entry)
    }
}


func hexNum<T: BinaryInteger>(_ value: T, width: Int) -> String {
    let num = String(value, radix: 16)
    if num.count <= width {
        return String(repeating: "0", count: width - num.count) + num
    }
    return num
}


func showRegisters(_ vcpu: VirtualMachine.VCPU) {
    var registers = ""

    func showReg(_ name: String, _ value: UInt16) {
        let w = hexNum(value, width: 4)
        registers += "\(name): \(w) "
    }

    showReg("CS", vcpu.registers.cs.selector)
    showReg("SS", vcpu.registers.ss.selector)
    showReg("DS", vcpu.registers.ds.selector)
    showReg("ES", vcpu.registers.es.selector)
    showReg("FS", vcpu.registers.fs.selector)
    showReg("GS", vcpu.registers.gs.selector)
    debugLog(registers)
    registers = "FLAGS \(vcpu.registers.rflags)"
    showReg("IP", vcpu.registers.ip)
    showReg("AX", vcpu.registers.ax)
    showReg("BX", vcpu.registers.bx)
    showReg("CX", vcpu.registers.cx)
    showReg("DX", vcpu.registers.dx)
    showReg("DI", vcpu.registers.di)
    showReg("SI", vcpu.registers.si)
    showReg("BP", vcpu.registers.bp)
    showReg("SP", vcpu.registers.sp)
    debugLog(registers)
}



func dumpMemory(_ memory: MemoryRegion, offset: Int, count: Int) {
    let ptr = memory.rawBuffer.baseAddress!.advanced(by: offset)
    let buffer = UnsafeRawBufferPointer(start: ptr, count: count)

    var idx = 0
    var output = "\(hexNum(offset + idx, width: 5)): "
    for byte in buffer {
        output += hexNum(byte, width: 2)
        output += " "
        idx += 1
        if idx == count { break }
        if idx.isMultiple(of: 16) {
            debugLog(output)
            output = "\(hexNum(offset + idx, width: 5)): "
        }
    }
    debugLog(output)
}


private var vmExitCount = UInt64(0)
func processVMExit(_ vcpu: VirtualMachine.VCPU, _ vmExit: VMExit) throws -> Bool {
    vmExitCount += 1

    switch vmExit {
        case .ioOutOperation(let port, let data):
            if case VMExit.DataWrite.word(let value) = data {
                let ip = UInt64(vcpu.registers.cs.base) + vcpu.registers.rip
                // Is call from BIOS?
                if (port >= 0xE0 && port <= 0xEF) && (ip >= 0xFF000 && ip <= 0xFFFFF) {
                    try biosCall(vm: vcpu.vm, subSystem: port, function: value)
                    break
                } else {
                    debugLog("Port: \(String(port, radix: 16)) IP: \(String(ip, radix: 16))")
                    debugLog("Not a bios call")
                }

            }
            try ISA.ioOut(port: port, dataWrite: data)

        case .ioInOperation(let port, let dataRead):
            let data = ISA.ioIn(port: port, dataRead: dataRead)
            debugLog("ioIn(0x\(String(port, radix: 16)), \(dataRead) => \(data))")
            vcpu.setIn(data: data)

        case .memoryViolation:
            //print(vmExit)
            //print("Ignoring violation:", violation)
            break

        case .exception(let exceptionInfo):
            showRegisters(vcpu)
            let offset = Int(vcpu.registers.cs.base) + Int(vcpu.registers.ip)
            dumpMemory(vcpu.vm.memoryRegions[0], offset: offset, count: 16)

            fatalError("\(vmExit): \(exceptionInfo)")

        case .debug(let debug):
            showRegisters(vcpu)
            fatalError("\(vmExit): \(debug)")

        case .hlt:
            debugLog("HLT... exiting")
            showRegisters(vcpu)
            return true


        default:
            debugLog(vmExit)
            showRegisters(vcpu)
            fatalError("Unhandled exit: \(vmExit)")
    }
    ISA.processHardware()
    return false
}



private var vmThread: Thread!
func runVMThreadWith(config: MachineConfig) {

    vmThread = Thread {
        let vm: VirtualMachine

        do {
            vm = try setupVMWith(config: config)
        }  catch {
            fatalError("Error: \(error)")
        }

        let group = DispatchGroup()
        group.enter()
        let vcpu = vm.vcpus[0]
        vcpu.completionHandler = {
            group.leave()
        }
        vcpu.start()
        debugLog("Waiting for VCPU to finish")
        group.wait()
        debugLog("VCPU has finished")
    }
    vmThread.start()
}


func setupVMWith(config: MachineConfig) throws -> VirtualMachine {
    let vm = try VirtualMachine()
    try vm.createVCPU(startup: { $0.setupRealMode() }, vmExitHandler: processVMExit)

    // Currently only KVM will emulate an PIC and PIT, HVF will not. The PIC/PIT code needs to be added into
    // HypervisorKit then it can be enabled there for HVF and the KVM one used on Linux.
    // try vm.addPICandPIT()

    ram = try vm.addMemory(at: 0, size: 0xA0_000) // 640K RAM everything above is Video RAM and ROM
    hma = try vm.addMemory(at: 0x100_000, size: 0x10_000) // HMA 64KB ram at 1MB mark
    // Top 4K
    let biosRegion = try vm.addMemory(at: 0xFF000, size: 4096)
    let biosImage = try Data(contentsOf: config.biosURL)
    try biosRegion.loadBinary(from: biosImage, atOffset: 0x0)
    try ISA.registerHardware(config: config, vm: vm)
    return vm
}


func main() {
    let config = MachineConfig(CommandLine.arguments.dropFirst(1))
    debugLog("Config:", config)

    if config.textMode {
        cursesStartupWith(config: config)
    } else {
        startupWith(config: config)
    }
}


main()
