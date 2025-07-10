import XCTest

@testable import SupplyDemand

final class SupplyDemandTests: XCTestCase {

    func testRootSupplierCalled() async throws {
        let expectation = expectation(description: "root supplier called")
        let mainSupplier: Supplier<Void?, String> = { _, _ in
            expectation.fulfill()
            return "HELLO"
        }
        let map: [String: AnySupplier] = [:]
        let result = try await supplyDemand(mainSupplier, map: map) as! String
        XCTAssertEqual(result, "HELLO")
        await fulfillment(of: [expectation], timeout: 1)
    }

    func testAdditionalSupplierUsed() async throws {
        let plusOneSupplier: AnySupplier = { input, _ in
            let val = input as! Int
            return val + 1
        }
        let mainSupplier: Supplier<Void?, Int> = { _, scope in
            let plusTwoSupplier: AnySupplier = { input, _ in
                let val = input as! Int
                return val + 2
            }

            guard
                let result = try await scope.demand(
                    "plustwo", 5,
                    ExtendSuppliers(add: ["plustwo": plusTwoSupplier])
                ) as? Int
            else {
                XCTFail("Did not get expected Int from supplier")
                return -1
            }
            return result
        }
        let map: [String: AnySupplier] = ["plusone": plusOneSupplier]
        let result = try await supplyDemand(mainSupplier, map: map) as! Int
        XCTAssertEqual(result, 7)
    }

    func testExtendSuppliersRemove() async throws {
        let supplierA: AnySupplier = { _, _ in "A" }
        let supplierB: AnySupplier = { _, _ in "B" }

        let mainSupplier: Supplier<Void?, String> = { _, scope in
            // Remove B from context:
            guard
                let result = try await scope.demand(
                    "A", nil,
                    ExtendSuppliers(remove: ["B": true])
                ) as? String
            else {
                XCTFail("Did not get expected String from supplier A")
                return ""
            }
            // Now, demanding "B" should throw an error
            do {
                _ = try await scope.demand("B", nil, ExtendSuppliers(remove: ["B": true]))
                XCTFail("Demanding B should have thrown, but it succeeded.")
            } catch SupplyDemandError.supplierNotFound(let type) {
                XCTAssertEqual(type, "B")
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
            return result
        }
        let map: [String: AnySupplier] = ["A": supplierA, "B": supplierB]
        let result = try await supplyDemand(mainSupplier, map: map) as! String
        XCTAssertEqual(result, "A")
    }

    func testExtendSuppliersClearAndAdd() async throws {
        let supplierA: AnySupplier = { _, _ in "A" }
        let supplierB: AnySupplier = { _, _ in "B" }
        let supplierC: AnySupplier = { _, _ in "C" }

        let mainSupplier: Supplier<Void?, String> = { _, scope in
            guard
                let result = try await scope.demand(
                    "C", nil,
                    ExtendSuppliers(add: ["C": supplierC], clear: true)
                ) as? String
            else {
                XCTFail("Did not get expected String from supplier C")
                return ""
            }
            return result
        }
        let map: [String: AnySupplier] = ["A": supplierA, "B": supplierB]
        let result = try await supplyDemand(mainSupplier, map: map) as! String
        XCTAssertEqual(result, "C")
    }

    func testDelayedAsyncSupplier() async throws {
        let expectation = expectation(description: "delayed supplier returns after 2 seconds")
        let delayedSupplier: AnySupplier = { input, _ in
            let val = input as! Int
            try await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds
            return val * 2
        }
        let mainSupplier: Supplier<Void?, Int> = { _, scope in
            guard
                let result = try await scope.demand(
                    "delayed", 21,
                    ExtendSuppliers(add: ["delayed": delayedSupplier])
                ) as? Int
            else {
                XCTFail("Did not get expected Int from supplier")
                return -1
            }
            return result
        }
        let map: [String: AnySupplier] = ["delayed": delayedSupplier]

        let start = Date()
        let result = try await supplyDemand(mainSupplier, map: map) as! Int
        let duration = Date().timeIntervalSince(start)
        XCTAssertEqual(result, 42)
        XCTAssert(duration >= 1.9, "Delay was too short: \(duration)")
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 3)
    }

    func testMissingSupplierThrows() async throws {
        let mainSupplier: Supplier<Void?, String> = { _, scope in
            try await scope.demand("missing", nil, ExtendSuppliers()) as! String
        }
        do {
            _ = try await supplyDemand(mainSupplier, map: [:])
            XCTFail("Expected thrown error")
        } catch SupplyDemandError.supplierNotFound(let type) {
            XCTAssertEqual(type, "missing")
        }
    }

    actor Counter {
        private(set) var value: Int = 0
        func increment(by amount: Int) {
            value += amount
        }
        func getValue() -> Int {
            value
        }
    }

    func testCachedSupplierInSupplyDemand() async throws {
        let counter = Counter()

        let incrementSupplier: Supplier<Int, Int> = { input, _ in
            await counter.increment(by: input)
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return await counter.getValue()
        }

        let cachedIncrement = cached(incrementSupplier)

        let mainSupplier: Supplier<Void?, [Int]> = { _, scope in
            // Both calls should see the same cached result
            let task1 = Task { try await scope.demand("inc", 10, ExtendSuppliers()) as! Int }
            let task2 = Task { try await scope.demand("inc", 10, ExtendSuppliers()) as! Int }

            let first = try await task1.value
            let second = try await task2.value

            return [first, second]
        }

        let map: [String: AnySupplier] = [
            "inc": { input, scope in
                try await cachedIncrement(input as! Int, scope)
            }
        ]

        let result = try await supplyDemand(mainSupplier, map: map) as! [Int]
        XCTAssertEqual(result, [10, 10])
    }

    func testCachedInFlightSupplierInSupplyDemand() async throws {
        let counter = Counter()

        let incrementSupplier: Supplier<Int, Int> = { input, _ in
            await counter.increment(by: input)
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return await counter.getValue()
        }

        let cachedIncrement = cachedInFlightOnly(incrementSupplier)

        let mainSupplier: Supplier<Void?, [Int]> = { _, scope in
            // Both calls should see the same cached result
            let task1 = Task { try await scope.demand("inc", 10, ExtendSuppliers()) as! Int }
            let task2 = Task { try await scope.demand("inc", 10, ExtendSuppliers()) as! Int }

            let first = try await task1.value
            let second = try await task2.value

            // After resolution next call will freshly trigger supplier
            let task3 = Task { try await scope.demand("inc", 10, ExtendSuppliers()) as! Int }

            let third = try await task3.value

            return [first, second, third]
        }

        let map: [String: AnySupplier] = [
            "inc": { input, scope in
                try await cachedIncrement(input as! Int, scope)
            }
        ]

        let result = try await supplyDemand(mainSupplier, map: map) as! [Int]
        XCTAssertEqual(result, [10, 10, 20])
    }

}
