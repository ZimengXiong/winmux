import DeckCore
import Foundation
import XCTest

final class DeckProfileParserTests: XCTestCase {
    func testParsesDeckProfileWithWorkspaceAndTabGroupRoutes() throws {
        let profile = try DeckProfileParser.parse(
            """
            name = "winmux"
            root = "~/Projects/winmux"

            [env]
            PORT = "3000"

            [[actions]]
            name = "Editor"
            type = "shell"
            run = "code --new-window \\"$DECK_ROOT\\""

            [actions.route]
            workspace = "code"
            tab-group = "editor"

            [actions.match]
            bundle-id = "com.microsoft.VSCode"
            title-contains = "winmux"

            [[actions]]
            name = "Browser"
            type = "browser"
            app = "Google Chrome"
            urls = ["http://localhost:$PORT"]
            """,
        )

        XCTAssertEqual(profile.name, "winmux")
        XCTAssertEqual(profile.actions.count, 2)
        XCTAssertEqual(profile.actions[0].route?.workspace, "code")
        XCTAssertEqual(profile.actions[0].route?.tabGroup, "editor")
        XCTAssertEqual(profile.actions[0].match?.bundleId, "com.microsoft.VSCode")
        XCTAssertEqual(try profile.actions[1].resolvedType(), .browser)
    }

    func testExpandsDeckVariables() {
        let expanded = DeckVariableResolver.expand(
            "$DECK_ROOT/${PORT}/$UNKNOWN",
            using: ["DECK_ROOT": "/tmp/project", "PORT": "3000"],
        )

        XCTAssertEqual(expanded, "/tmp/project/3000/")
    }

    func testResolverExpandsRootBeforeAssigningDeckRoot() {
        let profile = DeckProfile(name: "demo", root: "$HOME/project")
        let resolver = DeckVariableResolver(profile: profile)

        XCTAssertEqual(resolver.expand("$DECK_ROOT"), "\(FileManager.default.homeDirectoryForCurrentUser.path)/project")
    }

    func testStarterProfileParses() throws {
        let profile = try DeckProfileParser.parse(DeckStorage.starterProfile(name: "demo", root: "/tmp/demo"))

        XCTAssertEqual(profile.actions.count, 3)
    }

    func testInfersPlainUrlsAsUrlAction() throws {
        let action = DeckAction(urls: ["https://example.com"])

        XCTAssertEqual(try action.resolvedType(), .url)
    }
}
