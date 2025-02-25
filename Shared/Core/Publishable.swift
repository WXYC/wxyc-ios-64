@globalActor public actor PublishableActor: GlobalActor {
    public static let shared = PublishableActor()
}

@propertyWrapper
public final class Publishable<Value: Sendable>: Sendable {
    public typealias Observer = @Sendable @isolated(any) (Value) async -> ()

    public init(wrappedValue: Value) {
        self._wrappedValue = wrappedValue
    }
    
    public nonisolated func observe(observer: @escaping Observer) {
        Task { @PublishableActor in
            observers.append(observer)
        }
    }
    
    public var wrappedValue: Value {
        get {
            sync { self._wrappedValue }
        }
        set {
            Task { @PublishableActor in
                self._wrappedValue = newValue
                await self.updateObservers(with: newValue)
            }
        }
    }

    public var projectedValue: Publishable<Value> {
        self
    }
    
    // MARK: Private

    @PublishableActor
    private var _wrappedValue: Value
    
    @PublishableActor
    private var observers: [Observer] = []

    @PublishableActor
    private func updateObservers(with value: Value) async {
        for observer in observers {
            await observer(value)
        }
    }

    typealias Sync = @Sendable @PublishableActor () -> Value
    
    @inline(__always)
    private func sync(_ task: @escaping Sync) -> Value {
        var result: Value!
        let semaphore = DispatchSemaphore(value: 0)

        Task { @PublishableActor in
            result = task()
            semaphore.signal()
        }
        
        semaphore.wait()
        return result
    }
}
