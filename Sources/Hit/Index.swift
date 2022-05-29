//
//  Index.swift
//  LazyReview
//
//  Created by Honza Dvorsky on 07/02/2015.
//  Copyright (c) 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
/**
 *  The index is created in the following way

     [
         "token1": [
             "identifier1": [
                 range11, range12, range13, ...
             ],
             "identifier2": [
                 range21, range22, ...
             ], ...
         ],
         "token2": [
             ...
         ], ...
     ]

 The "identifier" can be anything that helps us look up the container of that text. A review, a file, ...
 So that when we find it, we can directly find that word at the specified range.

 The indexing itself will run in a map-reduce manner - indexing will run in multiple jobs
 and only when done we merge all results into the new index.
 */
final class Index {
    public typealias InputPair = (string: String, identifier: String)
    public typealias TokenRange = Range<String.Index>
    public typealias TokenRangeArray = [TokenRange] // MUST be sorted in ascending order
    public typealias TokenIndexData = [String: TokenRangeArray]
    public typealias TokenIndexPair = (token: String, data: TokenIndexData)
    public typealias IndexData = [String: TokenIndexData]

    private var indexStorage: IndexData = [:]
    private var trieStorage: Trie = .init(strings: [String]())

    public init() {}

    // PUBLIC API

    public func occurrencesOfToken(_ token: String) -> TokenIndexData? {
        indexStorage[normalizedToken(token)]
    }

    public func occurrencesOfTokensWithPrefix(_ prefix: String) -> [TokenIndexPair] {
        prefixSearch(prefix)
    }

    // returns when done, synchronous version
    public func updateIndexFromRawStringsAndIdentifiers(_ pairs: [InputPair]) {
        let newIndex = createIndexFromRawStringsAndIdentifiers(pairs)
        mergeNewDataIn(newIndex)
    }

    // try to hide the stuff below for testing eyes only

    // TODO: add an enum with a sort type - by Total Occurrences, Length, Unique Review Occurrences, ...
    public func prefixSearch(_ prefix: String) -> [TokenIndexPair] {
        let normalizedPrefix = normalizedToken(prefix)
        if normalizedPrefix.count < 2 {
            return [TokenIndexPair]() // don't return results under three chars (0, 1, 2).
        }

        // filter the keys that match the prefix
        // we're using a fast trie here
        let filtered = trieStorage.strings(matching: normalizedPrefix)

        // now sort them by length (I think that makes sense for prefix search - shortest match is the best)
        // if two are of the same length, sort those two alphabetically
        let sortedByLength = filtered.sorted { (s1: String, s2: String) -> Bool in
            let count1 = s1.count
            let count2 = s2.count

            if count1 == count2 {
                // now decide by alphabet
                return s1.localizedCaseInsensitiveCompare(s2) == ComparisonResult.orderedAscending
            }

            return count1 < count2
        }

        // now fetch index metadata for all the matches and return
        // TODO: count limiting?

        let result = sortedByLength.map { (token: $0, data: indexStorage[$0]!) }
        return result
    }

    public func createIndexFromRawStringsAndIdentifiers(_ pairs: [InputPair]) -> IndexData {
        let flattened = createIndicesFromRawStringsAndIdentifiers(pairs)
        let merged = binaryMerge(flattened)
        return merged
    }

    public func createIndicesFromRawStringsAndIdentifiers(_ pairs: [InputPair]) -> [IndexData] {
        let flattened = pairs.reduce([IndexData]()) { arr, item -> [IndexData] in
            arr + self.createIndicesFromRawString(item.string, identifier: item.identifier)
        }
        return flattened
    }

    private func threadSafeGetStorage() -> (index: IndexData, trie: Trie) {
        let indexStorage = self.indexStorage
        let trieStorage = self.trieStorage
        return (indexStorage, trieStorage)
    }

    public typealias ViewTokenCount = (token: String, count: Int)

    // aka number of occurrences total
    public func viewOfTokensSortedByNumberOfOccurrences() -> [ViewTokenCount] {
        var view = [ViewTokenCount]()

        for (token, tokenIndexData) in indexStorage {
            // get count of identifiers
            var rollingCount = 0
            for (_, identifierRangeArray) in tokenIndexData {
                rollingCount += identifierRangeArray.count
            }
            view.append((token: token, count: rollingCount))
        }

        // sort by number of occurrences
        view.sort { $0.count >= $1.count }

        return view
    }

    // aka number of reviews mentioning this word (doesn't matter how many times in one review)
    public func viewOfTokensSortedByNumberOfUniqueIdentifierOccurrences() -> [ViewTokenCount] {
        var view = [ViewTokenCount]()

        for (token, tokenIndexData) in indexStorage {
            // get count of identifiers
            let tokenCharCount = tokenIndexData.keys.count
            view.append((token: token, count: tokenCharCount))
        }

        // sort by number of occurrences
        view.sort { $0.count >= $1.count }

        return view
    }

    public func createIndicesFromRawString(_ string: String, identifier: String) -> [IndexData] {
        // iterate through the string
        var newIndices = [IndexData]()

        var substrings = [(Substring, Range<String.Index>)]()

        let stringRange = string.startIndex..<string.endIndex
        var remainingSubstring = string[stringRange]

        while let nextSpace = remainingSubstring.firstIndex(of: " ") {
            let range = remainingSubstring.startIndex..<nextSpace
            defer { remainingSubstring = string[string.index(after: nextSpace)..<string.endIndex] }

            guard !string[range].isEmpty else { continue }

            substrings.append((string[range], range))
        }

        substrings.append((remainingSubstring, remainingSubstring.startIndex..<remainingSubstring.endIndex))

        for (substring, substringRange) in substrings {
            // enumerating over tokens (words) and update index from each
            let newIndexData = createIndexFromToken(substring, range: substringRange, identifier: identifier)
            newIndices.append(newIndexData)
        }
        return newIndices
    }

    public func createIndexFromRawString(_ string: String, identifier: String) -> IndexData {
        let newIndices = createIndicesFromRawString(string, identifier: identifier)

        // TODO: measure and multithread

        // merge all those indices for each occurrence into one index
        let reduced = binaryMerge(newIndices)

        return reduced
    }

    public func reduceMerge(_ indexDataArray: [IndexData]) -> IndexData {
        // ok, now we have an array of new indices, merge them into one and return
        // This was pretty slow due to the first index getting large towards the end
        let reduced = indexDataArray.reduce(IndexData()) { bigIndex, newIndex -> IndexData in
            self.mergeIndexData(bigIndex, two: newIndex)
        }
        return reduced
    }

    /**
     Merges index data in pairs instead of having one big rolling index that every new one is merged with.
     */
    public func binaryMerge(_ indexDataArray: [IndexData]) -> IndexData {
        // termination condition 1
        if indexDataArray.count == 1 {
            return indexDataArray.first!
        }

        // termination condition 2
        if indexDataArray.count == 2 {
            return mergeIndexData(indexDataArray.first!, two: indexDataArray.last!)
        }

        var newIndexDataArray = [IndexData]()

        // go through and merge in neighbouring pairs
        var temp = [IndexData]()
        for i in 0..<indexDataArray.count {
            let second = temp.count == 1

            // if second, we're adding the second one, so let's merge
            temp.append(indexDataArray[i])
            if second {
                let merged = binaryMerge(temp)
                temp.removeAll(keepingCapacity: true)
                newIndexDataArray.append(merged)
            }
        }

        // if the count was odd, we have the last item unmerged with anyone, just add at the end of the new array
        if indexDataArray.count % 2 == 1 {
            newIndexDataArray.append(indexDataArray.last!)
        }

        return binaryMerge(newIndexDataArray)
    }

    private func createIndexFromToken(_ token: Substring, range: TokenRange, identifier: String) -> IndexData {
        let normalizedToken = self.normalizedToken(token)
        return [normalizedToken: [identifier: [range]]]
    }

    // this allows us to have multithreaded indexing and only at the end modify shared state :)
    private func mergeNewDataIn(_ newData: IndexData) {
        // merge these two structures together and keep the result
        indexStorage = mergeIndexData(indexStorage, two: newData)

        // recreate the Trie (TODO: don't recreate the whole thing, make it easier to append to the existing Trie)
        trieStorage = Trie(strings: Array(indexStorage.keys))
    }

    private func normalizedToken(_ found: Substring) -> String {
        // just lowercase
        found.lowercased()
    }

    private func normalizedToken(_ found: String) -> String {
        // just lowercase
        found.lowercased()
    }
}

// merging
private extension Index {
    func mergeIndexData(_ one: IndexData, two: IndexData) -> IndexData {
        one.merging(two) {
            self.mergeTokenIndexData($0, two: $1)
        }
    }

    func mergeTokenIndexData(_ one: TokenIndexData, two: TokenIndexData) -> TokenIndexData {
        one.merging(two) { one, two -> TokenRangeArray in
            self.mergeTokenRangeArrays(one, two: two)
        }
    }

    func mergeTokenRangeArrays(_ one: TokenRangeArray, two: TokenRangeArray) -> TokenRangeArray {
        // merge arrays
        // 1. concat
        let both = one + two

        // 2. sort
        let sorted = both.sorted { $0.lowerBound <= $1.lowerBound }

        // 3. remove duplicates
        let result = sorted.reduce(TokenRangeArray()) { array, range -> TokenRangeArray in
            if let last = array.last {
                if last == range {
                    // we already have this range, don't add it again
                    return array
                }
            }

            // haven't seen this range before, add it
            return array + [range]
        }

        return result
    }
}
