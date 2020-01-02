import XCTest

import FakePCTests

var tests = [XCTestCaseEntry]()
tests += FakePCTests.allTests()
XCTMain(tests)
