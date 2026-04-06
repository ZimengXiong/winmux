private let snap_help_generated = """
Snap the focused window to a Rectangle-style unmanaged position.
"""

public struct SnapCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    fileprivate init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .snap,
        allowInConfig: true,
        help: snap_help_generated,
        flags: [
            "--window-id": optionalWindowIdFlag(),
        ],
        posArgs: [newMandatoryPosArgParser(\.action, parseSnapActionArg, placeholder: SnapAction.unionLiteral)],
    )

    public var action: Lateinit<SnapAction> = .uninitialized

    public init(rawArgs: [String], action: SnapAction) {
        self.commonState = .init(rawArgs.slice)
        self.action = .initialized(action)
    }

    public enum SnapAction: String, CaseIterable, Equatable, Sendable {
        case leftHalf = "left-half"
        case rightHalf = "right-half"
        case topHalf = "top-half"
        case bottomHalf = "bottom-half"
        case topLeft = "top-left"
        case topRight = "top-right"
        case bottomLeft = "bottom-left"
        case bottomRight = "bottom-right"
        case firstThird = "first-third"
        case centerThird = "center-third"
        case lastThird = "last-third"
        case firstTwoThirds = "first-two-thirds"
        case lastTwoThirds = "last-two-thirds"
        case maximize
    }
}

func parseSnapCmdArgs(_ args: StrArrSlice) -> ParsedCmd<SnapCmdArgs> {
    parseSpecificCmdArgs(SnapCmdArgs(rawArgs: args), args)
}

private func parseSnapActionArg(i: PosArgParserInput) -> ParsedCliArgs<SnapCmdArgs.SnapAction> {
    .init(parseEnum(i.arg, SnapCmdArgs.SnapAction.self), advanceBy: 1)
}

extension SnapCmdArgs.SnapAction {
}
