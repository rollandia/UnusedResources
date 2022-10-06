//
//  main.swift
//  UnusedResources
//
//  Created by r.r.amirova on 06.10.2022.
//

import Foundation

// MARK: - Constants

private enum Constants {
    static let swiftGenPrefix = "internal static let"
    static let generatedFilePath = "generated.swift"
    static let generatedFileName = "Localizable.swift"
}

// MARK: - File processing

let dispatchGroup = DispatchGroup.init()
let serialWriterQueue = DispatchQueue.init(label: "writer")

func findFilesIn(_ directories: [String], withExtensions extensions: [String]) -> [String] {
    let fileManager = FileManager.default
    var files = [String]()
    for directory in directories {
        guard let enumerator: FileManager.DirectoryEnumerator = fileManager.enumerator(atPath: directory) else {
            print("Failed to create enumerator for directory: \(directory)")
            return []
        }
        while let path = enumerator.nextObject() as? String {
            let fileExtension = (path as NSString).pathExtension.lowercased()
            if extensions.contains(fileExtension) {
                let fullPath = (directory as NSString).appendingPathComponent(path)
                if !(fullPath.contains(Constants.generatedFilePath) || fullPath.contains(Constants.generatedFileName)) {
                    files.append(fullPath)
                }
            }
        }
    }
    return files
}

func contentsOfFile(_ filePath: String) -> String {
    do {
        return try String(contentsOfFile: filePath)
    } catch {
        print("Cannot read file at \(filePath)")
        exit(1)
    }
}

func concatenateAllSourceCodeIn(_ directories: [String]) -> String {
    let sourceFiles = findFilesIn(directories, withExtensions: ["swift"])
    return sourceFiles.reduce("") { (accumulator, sourceFile) -> String in
        return accumulator + contentsOfFile(sourceFile)
    }
}

// MARK: - Identifier extraction

func extractStringIdentifiersFrom(_ stringsFile: String) -> [String] {
    return contentsOfFile(stringsFile)
        .components(separatedBy: "\n")
        .map    { $0.trimmingCharacters(in: CharacterSet.whitespaces) }
        .filter { $0.hasPrefix(Constants.swiftGenPrefix) }
        .map    { extractStringIdentifierFromTrimmedLine($0) }
}

func extractStringIdentifierFromTrimmedLine(_ line: String) -> String {
    let startBoundRange = line.range(of: Constants.swiftGenPrefix)
    let endBoundRange = line.range(of: " =")
    guard let startBound = startBoundRange?.upperBound else { return "" }
    guard let endBound = endBoundRange?.lowerBound else { return "" }

    let startIndex = line.index(after: startBound)
    let endIndex = line.index(before: endBound)
    let identifier = line[startIndex...endIndex]
    return String(identifier)
}

// MARK: - Unused identifier detection

func findStringIdentifiersIn(_ stringsFile: String, abandonedBySourceCode sourceCode: String) -> [String] {
    return extractStringIdentifiersFrom(stringsFile).filter { !sourceCode.contains($0) }
}

func stringsFile(_ stringsFile: String, without identifiers: [String]) -> String {
    return contentsOfFile(stringsFile)
        .components(separatedBy: "\n")
        .filter({ (line) in
            let lineIdentifier = extractStringIdentifierFromTrimmedLine(line.trimmingCharacters(in: CharacterSet.whitespaces))
            return identifiers.contains(lineIdentifier) == false
        })
        .joined(separator: "\n")
}

typealias StringsFileToAbandonedIdentifiersMap = [String: [String]]

func findUnusedIdentifiersIn(_ rootDirectories: [String], generatedFiles: [String]) -> StringsFileToAbandonedIdentifiersMap {
    var map = StringsFileToAbandonedIdentifiersMap()
    let sourceCode = concatenateAllSourceCodeIn(rootDirectories)
    for file in generatedFiles {
        dispatchGroup.enter()
        DispatchQueue.global().async {
            let abandonedIdentifiers = findStringIdentifiersIn(file, abandonedBySourceCode: sourceCode)
            if abandonedIdentifiers.isEmpty == false {
                serialWriterQueue.async {
                    map[file] = abandonedIdentifiers
                    dispatchGroup.leave()
                }
            } else {
                NSLog("\(file) has no abandonedIdentifiers")
                dispatchGroup.leave()
            }
        }
    }
    dispatchGroup.wait()
    return map
}

// MARK: - Engine

func getCommandLineArgs() -> [String]? {
    var c = [String]()
    for arg in CommandLine.arguments {
        c.append(arg)
    }
    c.remove(at: 0)
    return c
}

func displayAbandonedIdentifiersInMap(_ map: StringsFileToAbandonedIdentifiersMap) {
    for file in map.keys.sorted() {
        print("\(file)")
        for identifier in map[file]!.sorted() {
            print("  \(identifier)")
        }
        print("")
    }
}

if let args = getCommandLineArgs(), let roodDirectory = args.first {
    print("Searching for unused resources…")
    let map = findUnusedIdentifiersIn([roodDirectory], generatedFiles: Array(args.dropFirst()))
    if map.isEmpty {
        print("No unused resource strings were detected.")
    } else {
        print("Unused resource strings were detected:")
        displayAbandonedIdentifiersInMap(map)
    }
} else {
    print("Please provide the root directory for source code files as a command line argument.")
}

