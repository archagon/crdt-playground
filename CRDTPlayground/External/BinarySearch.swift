// https://stackoverflow.com/a/31904569/89812
// modified to return the index of the closest element <= to searchItem, or nil if there are no elements
// TODO: check for correctness
// TODO: https://github.com/apple/swift-evolution/blob/master/proposals/0074-binary-search.md
func binarySearch<A:BidirectionalCollection, T:Comparable>(inputArr:A, searchItem:T, exact:Bool=true) -> A.IndexDistance? where A.Element == T {
    if inputArr.isEmpty {
        return nil
    }
    
    var lowerIndex: A.IndexDistance = 0
    var upperIndex: A.IndexDistance = inputArr.count - 1
    
    while (true) {
        let currentIndex = (lowerIndex + upperIndex) / 2
        let currentIndexObj = inputArr.index(inputArr.startIndex, offsetBy: currentIndex)
        var lastValidIndex = currentIndex
        var lastValidIndexObj = currentIndexObj //for fuzzy returns; cannot be negative since we check for empty array
        
        if (inputArr[currentIndexObj] == searchItem) {
            return currentIndex
        } else if (lowerIndex > upperIndex) {
            if exact {
                return nil
            }
            else {
                if inputArr[lastValidIndexObj] < searchItem {
                    return lastValidIndex
                }
                else {
                    if lastValidIndex == 0 {
                        return nil
                    }
                    else {
                        return lastValidIndex - 1
                    }
                }
            }
        } else {
            lastValidIndex = currentIndex
            lastValidIndexObj = currentIndexObj
            
            if (inputArr[currentIndexObj] > searchItem) {
                upperIndex = currentIndex - 1
            } else {
                lowerIndex = currentIndex + 1
            }
        }
    }
}
