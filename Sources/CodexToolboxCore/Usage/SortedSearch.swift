import Foundation

/// The predicate must be false before the boundary and true from it onwards.
enum SortedSearch {
    static func firstIndex<Element>(in values: [Element], where predicate: (Element) -> Bool) -> Int {
        var lower = 0, upper = values.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if predicate(values[middle]) { upper = middle } else { lower = middle + 1 }
        }
        return lower
    }
}
