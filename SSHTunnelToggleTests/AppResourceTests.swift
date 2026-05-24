import AppKit
import XCTest

final class AppResourceTests: XCTestCase {
    func testStatusBarIconAssetIsAvailable() {
        XCTAssertNotNil(NSImage(named: "StatusBarIcon"))
    }

    func testAppIconIsDeclaredInBundle() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String, "AppIcon")
        XCTAssertNotNil(Bundle.main.path(forResource: "AppIcon", ofType: "icns"))
    }
}
