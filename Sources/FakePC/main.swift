import Foundation
import HypervisorKit



private var fakePC: FakePC!


func debugLog(_ arguments: Any..., separator: String = " ") {
    var entry = ""

    var sep = ""
    for arg in arguments {
        entry += "\(arg)"
        entry += sep
        sep = separator
    }

    if let console = fakePC?.isa.console {
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


func main() {
    let config = MachineConfig(CommandLine.arguments.dropFirst(1))
    debugLog("Config:", config)

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


main()
