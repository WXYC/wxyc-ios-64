import Foundation

class Future<Value> {
    fileprivate var result: Result<Value>? {
        didSet { result.map(report) }
    }
    
    private lazy var callbacks = [(Result<Value>) -> Void]()
    
    func observe(with callback: @escaping (Result<Value>) -> Void) {
        callbacks.append(callback)
        result.map(callback)
    }
        
    private func report(result: Result<Value>) {
        for callback in callbacks {
            callback(result)
        }
    }
}


extension Future {
    enum FutureError: Error {
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
    
    static func ||(lhs: Future, rhs: Future) -> Future {
        let promise = Promise<Value>()
        
        lhs.observe { result in
            switch result {
            case let .success(value):
                promise.resolve(with: value)
            case .error(let firstError):
                rhs.observe(with: { imageResult in
                    switch imageResult {
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

struct CombinedError: Error {
    let first: Error
    let second: Error
    
    init(_ first: Error, _ second: Error) {
        self.first = first
        self.second = second
    }
}

class Promise<Value>: Future<Value> {
    init(value: Value? = nil) {
        super.init()
        result = value.map(Result.success)
    }
    
    func resolve(with value: Value) {
        result = .success(value)
    }
    
    func reject(with error: Error) {
        print("rejected: \(error.localizedDescription)")
        result = .error(error)
    }
}

extension URLSession {
    func request(url: URL) -> Future<Data> {
        let promise = Promise<Data>()
        
        let task = dataTask(with: url) { data, _, error in
            if let error = error {
                promise.reject(with: error)
            } else {
                promise.resolve(with: data ?? Data())
            }
        }
        
        task.resume()
        
        return promise
    }
}
