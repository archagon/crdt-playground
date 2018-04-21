//
//  ORDTTestUtils.swift
//  ORDTTests
//
//  Created by Alexei Baboulevitch on 2018-4-20.
//  Copyright © 2018 Alexei Baboulevitch. All rights reserved.
//

import Foundation
import CRDTFramework_OSX

func validate<T: ORDT>(_ ordt: inout T) -> Bool
{
    do
    {
        let v = try ordt.validate()
        return v
    }
    catch
    {
        print("Error: \(error)")
        return false
    }
}
func validate<T: ORDT>(_ ordt: inout T!) -> Bool
{
    do
    {
        let v = try ordt.validate()
        return v
    }
    catch
    {
        print("Error: \(error)")
        return false
    }
}
