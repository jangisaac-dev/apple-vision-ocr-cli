enum VOCRAppLifecyclePolicy {
    static func shouldTerminateAfterFinish(_ state: VOCRRunState) -> Bool {
        switch state {
        case .completed, .canceled, .failed:
            return true
        case .idle, .running, .paused:
            return false
        }
    }
}
