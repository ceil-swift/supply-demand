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

// The punctuation supplier, returns "!"
let punctuationSupplier: AnySupplier = { _, _ in
    return "!"
}

// The hello supplier, which itself demands punctuation from the current context:
let helloSupplier: AnySupplier = { input, scope in
    let name = input as! String
    // Query for the punctuation in the current scope:
    let punctuation = try await scope.demand("punctuation", nil, .init()) as! String
    return "Hello, \(name)\(punctuation)"
}

// The main supplier dynamically overrides the punctuation supplier:
let mainSupplier: Supplier<Void?, String> = { _, scope in
    // Override punctuation with "?"
    let result = try await scope.demand(
        "hello", "World", 
        ExtendSuppliers(
            add: ["punctuation": { _, _ in "?" }]
        )
    ) as! String
    return result
}

// Register your suppliers:
let map: [String: AnySupplier] = [
    "hello": helloSupplier,
    "punctuation": punctuationSupplier
]

// Run the composition:
let result = try await supplyDemand(mainSupplier, map: map) as! String
print(result) // Output: Hello, World?
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

### Swift Package Manager

Add **SupplyDemand** to your project using Swift Package Manager.

#### Via Xcode:

1. Go to **File > Add Packages...**
2. Enter the repository URL:
   ```
   https://github.com/ceil-swift/supply-demand.git
   ```
3. Choose the latest version and finish the dialog.

#### Via `Package.swift`:

Add the package into your project’s dependencies:
```swift
dependencies: [
    .package(url: "https://github.com/ceil-swift/supply-demand.git", from: "0.0.2")
]
```

And add `"SupplyDemand"` to the target’s dependencies:
```swift
.target(
    name: "YourTarget",
    dependencies: [
        "SupplyDemand"
    ]
)
```

---

## License

MIT