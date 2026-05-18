extension TreeNode {
    @MainActor
    var tabRepresentativeWindow: Window? {
        self as? Window ?? mostRecentWindowRecursive ?? anyLeafWindowRecursive
    }
}
