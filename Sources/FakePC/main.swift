import Foundation
import HypervisorKit
import Logging


private var fakePC: FakePC!
let logger: Logger = {
    LoggingSystem.bootstrap(StreamLogHandler.standardError)
    var logger = Logger(label: "org.si.FakePC")
    logger.logLevel = .error
    return logger
}()


func main() {
    let config = MachineConfig(CommandLine.arguments.dropFirst(1))
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


main()
