//
//  Utils.swift
//  TFTP
//
//  Created by Clément Mangin on 2017-10-18.
//  Copyright © 2017 Clément Mangin. All rights reserved.
//

import Foundation

// Credits to http://stackoverflow.com/questions/24034544/dispatch-after-gcd-in-swift/25120393#25120393

typealias dispatch_cancelable_closure = (_ cancel : Bool) -> Void

func delay(_ time: TimeInterval, closure: @escaping () -> Void) -> dispatch_cancelable_closure? {
    
    func dispatch_later(clsr: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + time, execute: clsr)
    }
    
    var closure: (() -> Void)? = closure
    var cancelableClosure: dispatch_cancelable_closure?
    
    let delayedClosure: dispatch_cancelable_closure = { cancel in
        if let closure = closure {
            if !cancel {
                DispatchQueue.main.async(execute: closure)
            }
        }
        closure = nil
        cancelableClosure = nil
    }
    
    cancelableClosure = delayedClosure
    
    dispatch_later {
        if let delayedClosure = cancelableClosure {
            delayedClosure(false)
        }
    }
    
    return cancelableClosure;
}

func cancel_delay(_ closure: dispatch_cancelable_closure?) {
    
    if closure != nil {
        closure!(true)
    }
}
