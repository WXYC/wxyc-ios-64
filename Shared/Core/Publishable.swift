@propertyWrapper public class Publishable<Value> {
    public typealias Observer = (Value) -> ()
    
    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
    
    public var wrappedValue: Value {
        didSet {
            self.updateObservers(with: wrappedValue)
        }
    }
    
    private var observers: [Observer] = []
    
    public func observe(observer: @escaping Observer) {
        observers.append(observer)
    }
    
    private func updateObservers(with value: Value) {
        for o in observers {
            o(value)
        }
    }
    
    public var projectedValue: Publishable<Value> {
        self
    }
}
