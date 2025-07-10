# SupplyDemand

A flexible, async-first dependency supply/demand and injection framework for Swift.

---

## Features

- ⚡️ **Async and type-erased suppliers**  
- 🔁 **Dynamic supplier registration/removal per scope or call**
- 🛠 **Easy dependency mocking for testing**
- 📦 **Built-in caching wrappers**

---

## Usage Example

### Registering and Using Suppliers

```swift
import SupplyDemand

let helloSupplier: AnySupplier = { input, _ in
    return "Hello, \(input as! String)!"
}

// Main supplier uses Scope to request other suppliers:
let mainSupplier: Supplier<Void?, String> = { _, scope in
    return try await scope.demand("hello", "World", .init()) as! String
}

let map: [String: AnySupplier] = ["hello": helloSupplier]

// Start a demand session:
let result = try await supplyDemand(mainSupplier, map: map) as! String
print(result) // Output: Hello, World!
```

### Extending Suppliers at Call Time

```swift
let goodbyeSupplier: AnySupplier = { input, _ in
    return "Goodbye, \(input as! String)!"
}

let customScope = ExtendSuppliers(add: ["goodbye": goodbyeSupplier])
let msg = try await scope.demand("goodbye", "Friend", customScope) as! String
```

---

## Caching a Supplier

```swift
let counter = Counter() // Your own actor
let incrementSupplier: Supplier<Int, Int> = { value, _ in
    await counter.increment(by: value)
    return await counter.getValue()
}

let cachedIncrement = cached(incrementSupplier)
```

---

## Error Handling

Demands to unregistered suppliers will throw:

```swift
do {
    try await scope.demand("missing", nil, .init())
} catch SupplyDemandError.supplierNotFound(let type) {
    print("Missing supplier: \(type)")
}
```

---

## Installation

Simply copy `SupplyDemand.swift` into your project, or add via SPM (when packaged).

---

## License

MIT