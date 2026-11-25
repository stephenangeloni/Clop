#!/usr/bin/env bash
set -euo pipefail

commit=89812896d072aa0928833b0d64f18906df09d429
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
dest="$(dirname "$repo_root")/Lowtech-local"

if [ -e "$dest" ] || [ -L "$dest" ]; then
    if grep -q "$commit" "$dest/ORIGIN.txt" 2>/dev/null; then
        echo "$dest already exists at $commit"
        exit 0
    fi
    echo "$dest exists but is not a Lowtech-local copy of $commit; move it away first" >&2
    exit 1
fi

work="$(mktemp -d "$(dirname "$repo_root")/Lowtech-local.partial.XXXXXX")"
trap 'rm -rf "$work"' EXIT

git clone --quiet https://github.com/FuzzyIdeas/Lowtech "$work/upstream"
git -C "$work/upstream" checkout --quiet "$commit"

mkdir -p "$work/out/Sources"
cp -R "$work/upstream/Sources/Lowtech" "$work/out/Sources/Lowtech"
sed -i '' 's/com\.lowtechguys\./com.stephenangeloni./g' \
    "$work/out/Sources/Lowtech/AppHangDetection.swift" \
    "$work/out/Sources/Lowtech/Logs.swift"

cat > "$work/out/Package.swift" <<'SWIFT'
// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "Lowtech",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "Lowtech", targets: ["Lowtech"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/Defaults", from: "9.0.0"),
        .package(url: "https://github.com/apple/swift-atomics", from: "1.0.2"),
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern", from: "1.0.0"),
        .package(url: "https://github.com/alin23/Magnet", from: "4.2.0"),
        .package(url: "https://github.com/Clipy/Sauce", from: "2.5.2"),
        .package(url: "https://github.com/yannickl/DynamicColor", from: "5.0.1"),
        .package(url: "https://github.com/diniska/swiftui-system-colors", from: "1.1.0"),
    ],
    targets: [
        .target(
            name: "Lowtech",
            dependencies: [
                .product(name: "Atomics", package: "swift-atomics"),
                .product(name: "Defaults", package: "Defaults"),
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern"),
                .product(name: "Magnet", package: "Magnet"),
                .product(name: "Sauce", package: "Sauce"),
                .product(name: "DynamicColor", package: "DynamicColor"),
                .product(name: "SystemColors", package: "swiftui-system-colors"),
            ]
        ),
    ]
)
SWIFT

echo "Pinned from commit $commit of github.com/FuzzyIdeas/Lowtech (Sources/Lowtech only). Not licensed for redistribution; keep out of public repos." > "$work/out/ORIGIN.txt"

mv "$work/out" "$dest"
echo "Created $dest"
