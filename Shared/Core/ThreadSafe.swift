import Foundation

final class ThreadSafe<Value> {
    private let queue = DispatchQueue(label: "org.wxyc.threadsafe")
    private var value: Value
    
    init(_ value: Value) {
        self.value = value
    }
    
    func mutate(_ work: (inout Value) -> Void) {
        queue.sync {
            work(&value)
        }
    }
    
    func access() -> Value {
        return queue.sync {
            return value
        }
    }
}
