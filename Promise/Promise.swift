//
//  Promise.swift
//  Promise
//
//  Created by Soroush Khanlou on 7/21/16.
//
//

import Foundation
import Dispatch

public protocol ExecutionContext {
    func execute(_ work: @escaping () -> Void)
}

extension DispatchQueue: ExecutionContext {
    public func execute(_ work: @escaping () -> Void) {
        self.async(execute: work)
    }
}

private extension Result {
    var value: Success? {
        guard case let .success(value) = self else { return nil }
        return value
    }

    var error: Failure? {
        guard case let .failure(error) = self else { return nil }
        return error
    }
}

public final class InvalidatableQueue: ExecutionContext {

    private var valid = true

    private var queue: DispatchQueue

    public init(queue: DispatchQueue = .main) {
        self.queue = queue
    }

    public func invalidate() {
        valid = false
    }

    public func execute(_ work: @escaping () -> Void) {
        guard valid else { return }
        self.queue.async(execute: work)
    }

}

struct Callback<Value> {
    let onFulfilled: (Value) -> Void
    let onRejected: (Error) -> Void
    let executionContext: ExecutionContext
    var completion: () -> Void
    
    func callFulfill(_ value: Value) {
        executionContext.execute({
            self.onFulfilled(value)
            self.completion()
        })
    }
    
    func callReject(_ error: Error) {
        executionContext.execute({
            self.onRejected(error)
            self.completion()
        })
    }
}

public final class Promise<Value> {
    
    private var state: Result<Value, Error>?
    private let lockQueue = DispatchQueue(label: "promise_lock_queue", qos: .userInitiated)
    private var callbacks: [Callback<Value>] = []
    
    public init() {
        state = nil
    }
    
    public init(value: Value) {
        state = .success(value)
    }
    
    public init(error: Error) {
        state = .failure(error)
    }
    
    public convenience init(queue: DispatchQueue = DispatchQueue.global(qos: .userInitiated), work: @escaping (_ fulfill: @escaping (Value) -> Void, _ reject: @escaping (Error) -> Void) throws -> Void) {
        self.init()
        queue.async(execute: {
            do {
                try work(self.fulfill, self.reject)
            } catch {
                self.reject(error)
            }
        })
    }

    /// - note: This one is "flatMap"
    @discardableResult
    public func then<NewValue>(on queue: ExecutionContext = DispatchQueue.main, _ onFulfilled: @escaping (Value) throws -> Promise<NewValue>) -> Promise<NewValue> {
        return Promise<NewValue>(work: { fulfill, reject in
            self.addCallbacks(
                on: queue,
                onFulfilled: { value in
                    do {
                        try onFulfilled(value).then(on: queue, fulfill, reject)
                    } catch {
                        reject(error)
                    }
                },
                onRejected: reject
            )
        })
    }
    
    /// - note: This one is "map"
    @discardableResult
    public func then<NewValue>(on queue: ExecutionContext = DispatchQueue.main, _ onFulfilled: @escaping (Value) throws -> NewValue) -> Promise<NewValue> {
        return then(on: queue, { (value) -> Promise<NewValue> in
            do {
                return Promise<NewValue>(value: try onFulfilled(value))
            } catch {
                return Promise<NewValue>(error: error)
            }
        })
    }
    
    @discardableResult
    public func then(on queue: ExecutionContext = DispatchQueue.main, _ onFulfilled: @escaping (Value) throws -> Void) -> Promise<Value> {
        return Promise(work: { (fulfill, reject) in
            self.addCallbacks(
                on: queue,
                onFulfilled: { (value) in
                    do {
                        try onFulfilled(value)
                        fulfill(value)
                    } catch {
                        reject(error)
                    }
                }, onRejected: reject
            )
        })
    }
    
    @discardableResult
    func then(on queue: ExecutionContext = DispatchQueue.main, _ onFulfilled: @escaping (Value) -> Void, _ onRejected: @escaping (Error) -> Void) -> Promise<Value> {
        addCallbacks(on: queue, onFulfilled: onFulfilled, onRejected: onRejected)
        return self
    }
    
    @discardableResult
    public func `catch`(on queue: ExecutionContext = DispatchQueue.main, _ onRejected: @escaping (Error) -> Void) -> Promise<Value> {
        return then(on: queue, { _ in }, onRejected)
    }
    
    public func reject(_ error: Error) {
        updateState(.failure(error))
    }
    
    public func fulfill(_ value: Value) {
        updateState(.success(value))
    }
    
    public var isPending: Bool {
        return !isFulfilled && !isRejected
    }
    
    public var isFulfilled: Bool {
        return value != nil
    }
    
    public var isRejected: Bool {
        return error != nil
    }
    
    public var value: Value? {
        return lockQueue.sync(execute: {
            return self.state?.value
        })
    }
    
    public var error: Error? {
        return lockQueue.sync(execute: {
            return self.state?.error
        })
    }
    
    private func updateState(_ state: Result<Value, Error>) {
        guard self.isPending else { return }
        lockQueue.sync(execute: {
            self.state = state
        })
        fireCallbacksIfCompleted()
    }
    
    private func addCallbacks(on queue: ExecutionContext = DispatchQueue.main, onFulfilled: @escaping (Value) -> Void, onRejected: @escaping (Error) -> Void) {
        let callback = Callback(onFulfilled: onFulfilled, onRejected: onRejected, executionContext: queue) {
            self.fireCallbacksIfCompleted()
        }
        lockQueue.async(execute: {
            self.callbacks.append(callback)
        })
        fireCallbacksIfCompleted()
    }
    
    private func fireCallbacksIfCompleted() {
        lockQueue.async(execute: {
            guard let callback = self.callbacks.first, self.state != nil else {
                return
            }
            self.callbacks.removeFirst()

            switch self.state {
            case let .success(value)?:
                callback.executionContext.execute {
                    callback.callFulfill(value)
                }
            case let .failure(error)?:
                callback.executionContext.execute {
                    callback.callReject(error)
                }
            default:
                break
            }
            
        })
    }
}
