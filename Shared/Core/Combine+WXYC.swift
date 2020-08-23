//
//  Combine+WXYC.swift
//  Core
//
//  Created by Jake Bromberg on 4/24/20.
//  Copyright © 2020 WXYC. All rights reserved.
//

import Foundation
import Combine

extension Cancellable {
    static func Combine(_ cancellables: Cancellable...) -> Cancellable {
        return AnyCancellable {
            for cancellable in cancellables {
                cancellable.cancel()
            }
        }
    }
}

public extension DispatchQueue {
    func async<T>(_ work: @escaping () throws -> T) -> AnyPublisher<T, Error> {
        let subject = PassthroughSubject<T, Error>()
        
        let work = {
            do {
                let value = try work()
                subject.send(value)
            } catch {
                subject.send(completion: .failure(error))
            }
        }
        
        self.async(execute: work)
        
        return subject.eraseToAnyPublisher()
    }
}

public extension Publisher {
    static func ||<U: Publisher>(lhs: Self, rhs: @autoclosure @escaping () -> U) -> AnyPublisher<Self.Output, U.Failure>
        where U.Output == Self.Output
    {
        lhs
            .catch { _ in rhs() }
            .eraseToAnyPublisher()
    }

    func compactMap<T>(_ keyPath: KeyPath<Self.Output, T?>) -> Publishers.CompactMap<Self, T> {
        return Publishers.CompactMap(upstream: self) { (output: Self.Output) -> T? in
            return output[keyPath: keyPath]
        }
    }
    
    func sink(_ receiveCompletion: @escaping ((Result<Self.Output, Self.Failure>) -> Void)) -> AnyCancellable {
        return sink(receiveCompletion: { completion in
            if case let .failure(failure) = completion {
                receiveCompletion(.failure(failure))
            }
        }) { output in
            receiveCompletion(.success(output))
        }
    }
    
    func onSuccess(_ completion: @escaping (Self.Output) -> Void) -> AnyCancellable {
        return sink { result in
            if case let .success(value) = result { completion(value) }
        }
    }
}
