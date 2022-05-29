//
//  Trie.swift
//  LazyReview
//
//  Created by Honza Dvorsky on 08/02/2015.
//  Copyright (c) 2015 Honza Dvorsky. All rights reserved.
//

import Foundation

private typealias SubTries = [String: TrieNode]

struct TrieNode {
    let token: String
    var endsWord: Bool
    var subNodes: [String: TrieNode]

    mutating func merge(with other: TrieNode) {
        assert(token == other.token, "Mergeable tries need to have the same token")

        endsWord = endsWord || other.endsWord
        subNodes = subNodes.merging(other.subNodes) {
            var result = $0
            result.merge(with: $1)
            return result
        }
    }

    var strings: [String] {
        let subNodes = Array(subNodes.values)

        // get substrings of `subNodes`
        var substrings = subNodes.map { (subNode: TrieNode) -> [String] in
            let substrings = subNode.strings
            // prepend our token to each
            let withToken = substrings.map { token + $0 }
            return withToken
        }.reduce([String]()) { rolling, item -> [String] in // flatten [[String]] to [String]
            rolling + item
        }

        if endsWord {
            // also add a new string ending with this token
            substrings.append(token)
        }

        return substrings
    }

    func findTrieEndingPrefix(_ prefix: String) -> TrieNode? {
        let length = prefix.count
        assert(length > 0, "Invalid arg: cannot be empty string")

        let prefixHeadRange = (prefix.startIndex..<prefix.index(prefix.startIndex, offsetBy: 1))
        let prefixHead = prefix[prefixHeadRange]
        let emptyTrie = token.count == 0

        if length == 1 && !emptyTrie {
            // potentially might be found if trie matches
            let match = (token == prefixHead)
            return match ? self : nil
        }

        let tokenMatches = token == prefixHead
        if emptyTrie || tokenMatches {
            // compute tail - the whole prefix if this was an empty trie
            let prefixTail = emptyTrie ? prefix : String(prefix[prefixHeadRange.upperBound...])

            // look into `subNodes`
            for subNode in subNodes.values {
                if let foundSubNode = subNode.findTrieEndingPrefix(prefixTail) {
                    return foundSubNode
                }
            }
        }
        return nil
    }
}

extension TrieNode {
    init() {
        self.init(token: "", endsWord: false, subNodes: SubTries())
    }

    init(_ string: String) {
        let headRange = (string.startIndex..<string.index(string.startIndex, offsetBy: 1))
        let head = String(string[headRange])

        let length = string.count
        if length > 1 {
            let tail = String(string[headRange.upperBound...])
            let subTrie = TrieNode(tail)
            let subNodes = [subTrie.token: subTrie]

            self.init(token: head, endsWord: false, subNodes: subNodes)
        } else {
            self.init(token: head, endsWord: true, subNodes: SubTries())
        }
    }

    init(_ strings: [String]) {
        let tries = strings.map { (string: String) -> TrieNode in
            // normalize first
            let normalized = string.lowercased()
            let trie = TrieNode(normalized)
            return trie
        }

        // we need all the tries to have an empty root so that we can merge them easily
        let triesWithRoots = tries.map { (trie: TrieNode) -> TrieNode in
            TrieNode(token: "", endsWord: false, subNodes: [trie.token: trie])
        }

        // now merge them
        self = triesWithRoots.reduce(into: TrieNode()) { (rollingTrie: inout TrieNode, thisTrie) in
            rollingTrie.merge(with: thisTrie)
        }
    }
}

public struct Trie {
    typealias TokenRange = Range<String.Index>
    let root: TrieNode

    public init(strings: [String]) {
        root = TrieNode(strings)
    }

    public func exportTrie() -> [String] {
        root.strings
    }

    public func strings(matching prefix: String) -> [String] {
        let normalized = prefix.lowercased()
        if let trieRoot = root.findTrieEndingPrefix(normalized) {
            let strings = trieRoot.strings
            let stringsWithPrefix = strings.map { (s: String) -> String in
                // here we take the last char out of the prefix, because it's already contained
                // in the found trie.
                String(normalized.dropLast()) + s
            }
            return stringsWithPrefix
        }
        return [String]()
    }

    // TODO: we learned in indexing that binary merge is much better than a rolling reduce
//    static func binaryMerge() {
//
//    }
}
