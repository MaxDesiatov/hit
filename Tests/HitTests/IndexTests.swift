//
//  IndexTests.swift
//  LazyReview
//
//  Created by Honza Dvorsky on 08/02/2015.
//  Copyright (c) 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
@testable import Hit
import XCTest

class IndexTests: HitTestCase {
    func rangeFromString(_ string: String, start: Int, count: Int) -> Index.TokenRange {
        let startIndex = string.startIndex
        let start = string.index(startIndex, offsetBy: start)
        let end = string.index(start, offsetBy: count)
        let range = (start..<end)
        return range
    }

    func testCreatingIndex() throws {
        let string1 =
            """
            Hello world how is your app SwiftKey doing?I hope well! Because it's surprisingly great!
            Yoyo how is this? SwiftKey rules the world!
            """
        let identifier1 = "review1"

        let string2 = "How amazing app this SwiftKey thing!"
        let identifier2 = "review2"
        let index = Index()

        let pairs = [
            (string: string1, identifier: identifier1),
            (string: string2, identifier: identifier2),
        ]

        index.updateIndexFromRawStringsAndIdentifiers(pairs)

        // now, examine the index
        let tokenIndexData = index.occurrencesOfToken("SwiftKey")

        guard let tokenIndexData = tokenIndexData else {
            XCTFail("No token index data was found")
            return
        }

        XCTAssertEqual(tokenIndexData.values.count, 2, "Should have occured in 2 identifiers")

        if let ranges = tokenIndexData["review1"] {
            // should be sorted
            let targetRange1 = rangeFromString(string1, start: 28, count: 8)
            let targetRange2 = rangeFromString(string1, start: 107, count: 8)
            XCTAssertEqual(ranges[0], targetRange1, "Ranges must equal")
            XCTAssertEqual(ranges[1], targetRange2, "Ranges must equal")

        } else {
            XCTFail("No ranges data for identifier review1")
        }

        if let ranges = tokenIndexData["review2"] {
            // should be sorted
            let targetRange = rangeFromString(string2, start: 21, count: 8)
            XCTAssertEqual(ranges[0], targetRange, "Ranges must equal")

        } else {
            XCTFail("No ranges data for identifier review2")
        }
    }

    // watch out - this might take minutes, runs the whole thing 10 times and the data is pretty large
    // takes seconds per run
    func testPerformance_fullIndexCreation() throws {
        let data = try parseTestingData()

        measure {
            guard let index = try? Index() else { return }
            let pairs = self.pairify(data)
            index.updateIndexFromRawStringsAndIdentifiers(pairs)
        }
    }

    func testCorrectness_indexMerging_reduce_binary() throws {
        let data = try parseTestingData()
        let pairs = pairify(data)
        let index = Index()

        let indices = index.createIndicesFromRawStringsAndIdentifiers(pairs)

        XCTAssertEqual(index.reduceMerge(indices), index.binaryMerge(indices))
    }

    func testPerformance_indexMerging_reduce() throws {
        let data = try parseTestingData()
        let pairs = pairify(data)
        let index = Index()

        let indices = index.createIndicesFromRawStringsAndIdentifiers(pairs)

        measure { () in
            _ = index.reduceMerge(indices)
        }
    }

    func testPerformance_indexMerging_binary() throws {
        let data = try parseTestingData()
        let pairs = pairify(data)
        let index = Index()

        let indices = index.createIndicesFromRawStringsAndIdentifiers(pairs)

        measure { () in

            _ = index.binaryMerge(indices)
        }
    }

    func testPrefixSearch() throws {
        let pairs = pairify(try parseTestingData())
        let index = Index()

        index.updateIndexFromRawStringsAndIdentifiers(pairs)

        // try to search for swiftkey by typing "sw"
        let results = index.prefixSearch("sw")
        let resultsMap = mapify(results)

        let expected = ["swipe", "swype", "swiping", "swiftkey", "swiftkey,", "switched", "switch"]

        if results.count != expected.count {
            XCTFail("Mismatch of count. Expected: \(expected), Received: \(Array(resultsMap.keys))")
        } else {
            for expectedToken in expected {
                if resultsMap[expectedToken] == nil {
                    // fail
                    XCTFail(
                        "Mismatch of expected and received results, didn't find expected token: \(expectedToken)"
                    )
                }
            }
        }
    }

    // utils
}
