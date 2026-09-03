func parseSpecificCmdArgs<T: CmdArgs>(_ raw: T, _ args: StrArrSlice) -> ParsedCmd<T> {
    var raw = raw
    var errors: [String] = []

    var posArgumentParserIndex = 0
    var options: Set<String> = Set()
    var index = 0
    var positionalOnly = false

    loop: while index < args.count {
        let arg = args[index]

        switch (positionalOnly, arg) {
            case (false, "-h"), (false, "--help"):
                return .help(T.info.help)
            case (false, _) where arg.isCliDashFlag && !isResizeNegativeUnitsArg(raw, arg: arg):
                if let optionParser = T.parser.flags[arg] {
                    index += 1
                    if !options.insert(arg).inserted {
                        errors.append("Duplicated option \(arg.singleQuoted)")
                    }
                    raw = optionParser.transformRaw(raw, &index, SubArgParserInput(superArg: arg, index: index, args: args), &errors)
                } else {
                    errors.append("Unknown flag \(arg.singleQuoted)")
                    break loop
                }
            default:
                if arg == "--" {
                    positionalOnly = true
                }
                if let parser = T.parser.positionalArgs.getOrNil(atIndex: posArgumentParserIndex) {
                    let input = PosArgParserInput(index: index, args: args, sawDashDash: positionalOnly)
                    raw = parser.transformRaw(raw, &index, input, &errors)
                    posArgumentParserIndex += 1
                } else {
                    errors.append("Unknown argument \(arg.singleQuoted)")
                    break loop
                }
        }
    }

    for arg in T.parser.positionalArgs[posArgumentParserIndex...] {
        if let placeholder = arg.context.argPlaceholderIfMandatory {
            errors.append("Argument \(placeholder.singleQuoted) is mandatory")
        }
    }

    for conflictSet in T.parser.conflictingOptions {
        let mutualOptions = conflictSet.intersection(options)
        if mutualOptions.count > 1 {
            errors.append("Conflicting options: \(mutualOptions.sorted().joined(separator: ", "))")
            break
        }
    }

    return errors.isEmpty ? .cmd(raw) : .failure(errors.joinErrors())
}

public enum ParsedCmd<T: Sendable>: Sendable {
    case cmd(T)
    case help(String)
    case failure(String)

    public func map<R>(_ mapper: (T) -> R) -> ParsedCmd<R> {
        flatMap { .cmd(mapper($0)) }
    }

    public func filter(_ msg: @autoclosure () -> String, _ predicate: (T) -> Bool) -> ParsedCmd<T> {
        flatMap { this in predicate(this) ? .cmd(this) : .failure(msg()) }
    }

    public func filterNot(_ msg: @autoclosure () -> String, _ predicate: (T) -> Bool) -> ParsedCmd<T> {
        flatMap { this in !predicate(this) ? .cmd(this) : .failure(msg()) }
    }

    public func flatMap<R>(_ mapper: (T) -> ParsedCmd<R>) -> ParsedCmd<R> {
        return switch self {
            case .cmd(let cmd): mapper(cmd)
            case .help(let help): .help(help)
            case .failure(let fail): .failure(fail)
        }
    }

    public var cmdOrNil: T? {
        switch self {
            case .cmd(let t): t
            default: nil
        }
    }

    public func unwrap() -> (T?, String?, String?) {
        switch self {
            case .cmd(let command):   (command, nil, nil)
            case .help(let help):     (nil, help, nil)
            case .failure(let error): (nil, nil, error)
        }
    }
}

extension ArgParserProtocol where Root: ConvenienceCopyable {
    fileprivate func transformRaw(_ raw: consuming Root, _ index: inout Int, _ input: Input, _ errors: inout [String]) -> Root {
        let parsedCliArgs = parse(input)
        index += parsedCliArgs.advanceBy
        if let value = parsedCliArgs.value.getOrNil(appendErrorTo: &errors) {
            return raw.copy(keyPath, value)
        } else {
            return raw
        }
    }
}

// Hack to preserve backwards compatibility
private func isResizeNegativeUnitsArg(_ raw: any CmdArgs, arg: String) -> Bool {
    var iter = arg.makeIterator()
    return raw is ResizeCmdArgs && iter.next() == "-" && iter.next()?.isNumber == true
}
