enum VOCRAppLifecyclePolicy {
    static func shouldTerminateAfterFinish(_ state: VOCRRunState) -> Bool {
        switch state {
        case .completed, .canceled:
            return true
        case .idle, .running, .paused, .failed:
            return false
        }
    }
}
