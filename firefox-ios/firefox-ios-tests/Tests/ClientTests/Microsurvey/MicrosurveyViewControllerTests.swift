// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest

@testable import Client

final class MicrosurveyViewControllerTests: XCTestCase {
    let windowUUID: WindowUUID = .XCTestDefaultUUID

    override class func setUp() {
        super.setUp()
        DependencyHelperMock().bootstrapDependencies()
    }

    override func tearDown() {
        super.tearDown()
        DependencyHelperMock().reset()
    }

    func testMicrosurveyViewController_simpleCreation_hasNoLeaks() {
        let microsurveyViewController = MicrosurveyViewController(windowUUID: windowUUID)
        trackForMemoryLeaks(microsurveyViewController)
    }
}
