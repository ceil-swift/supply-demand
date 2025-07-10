import Foundation

public enum SupplyDemandError: Error {
  case supplierNotFound(type: String)
}

public struct Scope: Sendable {
  public let demand:
    @Sendable (_ type: String, _ data: Any?, _ extendSuppliers: ExtendSuppliers) async throws -> Any

  public init(
    demand: @Sendable @escaping (_ type: String, _ data: Any?, _ extendSuppliers: ExtendSuppliers)
      async throws -> Any
  ) {
    self.demand = demand
  }
}

public struct ExtendSuppliers {
  public var add: [String: AnySupplier] = [:]
  public var remove: [String: Bool] = [:]
  public var clear: Bool = false

  public init(add: [String: AnySupplier] = [:], remove: [String: Bool] = [:], clear: Bool = false) {
    self.add = add
    self.remove = remove
    self.clear = clear
  }
}

public typealias Supplier<Input, Output> = @Sendable (Input, Scope) async throws -> Output
public typealias AnySupplier = @Sendable (Any, Scope) async throws -> Any

public func supplyDemand<Input, Output>(
  _ mainSupplier: @escaping Supplier<Input, Output>,
  map: [String: AnySupplier]
) async throws -> Any {
  let rootSupplier: AnySupplier = { (input: Any, scope: Scope) async throws -> Any in
    guard let typedInput = input as? Input else {
      fatalError(
        "Input type mismatch for mainSupplier. Expected \(Input.self), got \(type(of: input))")
    }
    return try await mainSupplier(typedInput, scope)
  }
  return try await globalDemand(
    type: "$$root",
    data: nil,
    suppliers: map,
    extendSuppliers: ExtendSuppliers(add: ["$$root": rootSupplier])
  )
}

internal func globalDemand(
  type: String,
  data: Any?,
  suppliers: [String: AnySupplier],
  extendSuppliers: ExtendSuppliers? = nil
) async throws -> Any {
  var updatedSuppliers = suppliers

  if let ext = extendSuppliers {
    if ext.clear {
      updatedSuppliers.removeAll()
    }
    for (key, _) in ext.remove {
      updatedSuppliers.removeValue(forKey: key)
    }
    for (key, supplier) in ext.add {
      updatedSuppliers[key] = supplier
    }
  }

  let scope = try await createScope(suppliers: updatedSuppliers)
  guard let supplier = updatedSuppliers[type] else {
    throw SupplyDemandError.supplierNotFound(type: type)
  }
  return try await supplier(data as Any, scope)
}

internal func createScope(
  suppliers: [String: AnySupplier]
) async throws -> Scope {
  return Scope { type, data, extendSuppliers in
    try await globalDemand(
      type: type, data: data, suppliers: suppliers, extendSuppliers: extendSuppliers)
  }
}

@available(macOS 10.15, *)
actor CacheBox<Input, Output: Sendable> {
  var result: Output?
  var inFlight: Task<Output, Error>?
  let cacheResults: Bool

  init(cacheResults: Bool = true) {
    self.cacheResults = cacheResults
  }

  func get(
    original: @escaping Supplier<Input, Output>,
    input: Input,
    scope: Scope
  ) async throws -> Output {
    if cacheResults, let result = result {
      return result
    }
    if let inFlight = inFlight {
      return try await inFlight.value
    }
    let task = Task {
      let value = try await original(input, scope)
      await setResult(value)
      return value
    }
    inFlight = task
    return try await task.value
  }

  private func setResult(_ value: Output) async {
    if cacheResults {
      self.result = value
    }
    self.inFlight = nil
  }
}

@available(macOS 10.15, *)
public func cached<Input: Sendable, Output: Sendable>(
  _ original: @escaping Supplier<Input, Output>
) -> Supplier<Input, Output> {
  let box = CacheBox<Input, Output>(cacheResults: true)
  return { input, scope in
    try await box.get(original: original, input: input, scope: scope)
  }
}

@available(macOS 10.15, *)
public func cachedInFlightOnly<Input: Sendable, Output: Sendable>(
  _ original: @escaping Supplier<Input, Output>
) -> Supplier<Input, Output> {
  let box = CacheBox<Input, Output>(cacheResults: false)
  return { input, scope in
    try await box.get(original: original, input: input, scope: scope)
  }
}
