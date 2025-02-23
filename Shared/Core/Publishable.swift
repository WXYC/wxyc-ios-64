@globalActor public actor PublishableActor: GlobalActor {
    public static let shared = PublishableActor()
}

@propertyWrapper
public final class Publishable<Value: Sendable>: Sendable {
    public typealias Observer = @Sendable @isolated(any) (Value) -> ()

    @PublishableActor
    private var _wrappedValue: Value
    @PublishableActor
    private var observers: [Observer] = []

    public init(wrappedValue: Value) {
        self._wrappedValue = wrappedValue
    }

    public var wrappedValue: Value {
        get {
            performTaskSynchronously { @PublishableActor in
                self._wrappedValue
            }
        }
        set {
            performTaskSynchronously { @PublishableActor in
                self._wrappedValue = newValue
            }
            self.updateObservers(with: newValue)
        }
    }

    public var projectedValue: Publishable<Value> {
        self
    }

    private func updateObservers(with value: Value) {
        Task { @PublishableActor in
            for observer in observers {
                await observer(value)
            }
        }
    }

    public nonisolated func observe(observer: @escaping Observer) {
        Task { @PublishableActor in
            observers.append(observer)
        }
    }
    
    typealias Sync = @Sendable @isolated(any) () -> Value
    func performTaskSynchronously(_ task: @escaping Sync) -> Value {
        var result: Value?
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            result = await task()
            semaphore.signal()
        }
        
        semaphore.wait()
        return result!
    }
    
    func performTaskSynchronously(_ task: @escaping @Sendable @isolated(any) () -> ()) {
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            semaphore.signal()
        }
        
        semaphore.wait()
    }
}
