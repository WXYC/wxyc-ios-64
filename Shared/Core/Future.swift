import Foundation

public class Future<Value> {
    typealias Callback = (Result<Value>) -> Void
    
    fileprivate var result: Result<Value>? {
        didSet { result.map(report) }
    }
    
    private lazy var callbacks = [Callback]()
    
    func observe(with callback: @escaping Callback) {
        callbacks.append(callback)
        result.map(callback)
    }
    
    func observe(with callbacks: [Callback]) {
        for callback in callbacks {
            self.observe(with: callback)
        }
    }
        
    private func report(result: Result<Value>) {
        for callback in callbacks {
            callback(result)
        }
    }
}


extension Future {
    enum FutureError: String, Error {
        case transformationFailure
    }
    
    func chained<NextValue>(with closure: @escaping (Value) throws -> Future<NextValue>) -> Future<NextValue> {
        let promise = Promise<NextValue>()
        
        observe { result in
            switch result {
            case .success(let value):
                do {
                    let future = try closure(value)
                    
                    future.observe { result in
                        switch result {
                        case .success(let value):
                            promise.resolve(with: value)
                        case .error(let error):
                            promise.reject(with: error)
                        }
                    }
                } catch {
                    promise.reject(with: error)
                }
            case .error(let error):
                promise.reject(with: error)
            }
        }
        
        return promise
    }
    
    func transformed<NextValue>(with closure: @escaping (Value) throws -> NextValue) -> Future<NextValue> {
        return chained { value in
            return try Promise(value: closure(value))
        }
    }
    
    func transformed<NextValue>(with closure: @escaping (Value) -> NextValue?) -> Future<NextValue> {
        return chained { value in
            if let value = closure(value) {
                return Promise(value: value)
            } else {
                throw FutureError.transformationFailure
            }
        }
    }
    
    public func onSuccess(_ closure: @escaping (Value) -> Void) {
        _ = transformed { value -> Void in
            closure(value)
        }
    }
    
    static func ||(lhs: Future, rhs: @escaping @autoclosure () -> (Future)) -> Future {
        let promise = Promise<Value>()
        
        lhs.observe { result in
            switch result {
            case let .success(value):
                promise.resolve(with: value)
            case .error(let firstError):
                rhs().observe(with: { result in
                    switch result {
                    case let .success(value):
                        promise.resolve(with: value)
                    case let .error(secondError):
                        promise.reject(with: CombinedError(firstError, secondError))
                    }
                })
            }
        }
        
        return promise
    }
    
    static func `repeat`(_ future: @escaping () -> (Future), timeInterval: TimeInterval = 30) -> Future {
        let promise = Promise<Value>()
        
        let timer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: true) { _ in
            future().observe(with: { result in
                switch result {
                case .success(let success):
                    promise.resolve(with: success)
                case .error(let error):
                    promise.reject(with: error)
                }
            })
        }
        
        timer.fire()
        
        return promise
    }
}

struct CombinedError: LocalizedError {
    let errorDescription: String
    
    init(_ first: Error, _ second: Error) {
        let descriptions: Set<String> = [first.localizedDescription, second.localizedDescription]
        self.errorDescription = descriptions.joined(separator: ", ")
    }
}

class Promise<Value>: Future<Value> {
    init(value: Value? = nil) {
        super.init()
        
        result = value.map(Result.success)
    }
    
    init(error: Error) {
        super.init()
        
        result = .error(error)
    }
    
    func resolve(with value: Value) {
        result = .success(value)
    }
    
    func reject(with error: Error) {
        print("rejected: \(error)")
        result = .error(error)
    }
}
