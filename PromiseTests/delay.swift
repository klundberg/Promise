//
//  delay.swift
//  Promise
//
//  Created by Soroush Khanlou on 8/2/16.
//
//

import XCTest
import Dispatch

internal func delay(_ duration: TimeInterval, block: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: {
        block()
    })
}


struct SimpleError: Error, Equatable {
    
}

struct AlternativeError: Error, Equatable {

}

func ==(lhs: SimpleError, rhs: SimpleError) -> Bool {
    return true
}
