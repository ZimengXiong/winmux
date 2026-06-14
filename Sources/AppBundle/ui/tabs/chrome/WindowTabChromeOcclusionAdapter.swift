import CoreGraphics

@MainActor
func cachedWindowTabOcclusions(
    workspaceName: String,
    cache: inout [String: [CGRect]],
) async -> [CGRect] {
    if let cached = cache[workspaceName] {
        return cached
    }
    let occlusions: [CGRect]
    if let workspace = Workspace.existing(byName: workspaceName) {
        occlusions = await windowTabOccludingFloatingWindowFrames(in: workspace)
    } else {
        occlusions = []
    }
    cache[workspaceName] = occlusions
    return occlusions
}
