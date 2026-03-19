# Swift Style Guide

## Naming

- Use **camelCase** for variables, functions, and properties
- Use **PascalCase** for types (classes, structs, enums, protocols)
- Use descriptive names; avoid abbreviations unless universally understood (`url`, `id`)
- Boolean properties read as assertions: `isEnabled`, `hasSession`, `canReset`
- Protocols describing capability use `-ing` or `-able`: `Configurable`, `SessionTracking`

## Formatting

- **4-space indentation** (Xcode default)
- Opening braces on the same line
- One blank line between function definitions
- No trailing whitespace
- Maximum line length: 120 characters (soft limit)

## Code Organization

- Group related properties and methods using `// MARK: -` comments
- Order within a type:
  1. Properties
  2. Initializers
  3. Lifecycle methods
  4. Public methods
  5. Private methods

## Types and Access Control

- Prefer `struct` over `class` when there's no need for reference semantics
- Use the most restrictive access level that works (`private` > `fileprivate` > `internal` > `public`)
- Mark classes `final` unless designed for subclassing
- Prefer `let` over `var` wherever possible

## Optionals

- Avoid force unwrapping (`!`) — use `guard let` or `if let` instead
- Use `??` for sensible defaults
- Optional chaining over nested `if let` when possible

## Closures

- Use trailing closure syntax for the last closure parameter
- Use shorthand arguments (`$0`, `$1`) only in short, obvious closures
- Capture `[weak self]` in closures that outlive the current scope

## Error Handling

- Use `do`/`catch` for recoverable errors
- Use `guard` for early returns on invalid state
- Avoid empty `catch` blocks — at minimum log the error

## Swift-Specific

- Prefer Swift native types (`String`, `Int`) over Objective-C bridged types
- Use `enum` for namespacing constants
- Prefer `map`, `filter`, `compactMap` over manual loops where readable
- Use extensions to conform to protocols in separate blocks
