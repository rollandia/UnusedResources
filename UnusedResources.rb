SWIFTGEN_PREFIX = "internal static let "
LOCALIZABLE_FILE = "Localizable.swift"
SWIFT_EXTENSION= ".swift"

# MARK: - File processing

def find_files_in(directories, extensions, exceptPaths = [])
    files = []
    for directory in directories do
    	records = Dir.glob("#{directory}/**/*").reject { |f| 
    		File.directory?(f) || !extensions.include?(File.extname(f)) || (exceptPaths.any? { |path| f.include?(path) })
    	}
    	files.concat records
    end
    return files
end

def contents_of_file(path)
	text = File.read(path)
end

def concatenate_all_source_code_in(directories) 
    source_files = find_files_in(directories, [SWIFT_EXTENSION], ["Generated", LOCALIZABLE_FILE])
    return source_files.reduce("") { |accumulator, sourceFile| accumulator + contents_of_file(sourceFile) }
end

# MARK: - Identifier extraction

def extract_string_identifiers_from(strings_file)
	return contents_of_file(strings_file)
		.split("\n")
		.map    { |string| string.strip }
		.select { |string| string.start_with?(SWIFTGEN_PREFIX) }
		.map    { |string| extract_string_identifier_from_trimmed_line(string) }
end

def extract_string_identifier_from_trimmed_line(line)
	line[/#{SWIFTGEN_PREFIX}(.*?)#{" ="}/m, 1]
end

# MARK: - Unused identifier detection

def find_string_identifiers_in(strings_file, source_code)
    ids = extract_string_identifiers_from(strings_file)

    return ids.select { |string|
        !source_code.include?(string)
    }
end

def find_unused_identifiers_in(root_directories, generated_files)
    map = Hash.new
    source_code = concatenate_all_source_code_in(root_directories)
    # puts root_directories
    # puts generated_files
    for file in generated_files
	    abandoned_identifiers = find_string_identifiers_in(file, source_code)
	    if !abandoned_identifiers.empty? 
            map[file] = abandoned_identifiers
	    else
	        puts "#{file} has no abandoned_identifiers"
	    end
	end
    return map
end

# MARK: - Engine

def display_abandoned_identifiers_in_map(map)
    for file in map.keys.sort!
        puts "#{file}"
        for identifier in map[file]
            puts "  #{identifier}"
        end
        puts ""
    end
end

if ARGV.length > 1
    puts "Searching for unused resources…"
    map = find_unused_identifiers_in([ARGV[0]], Array(ARGV.drop(1)))
    if map.empty? 
        puts "No unused resource strings were detected."
    else
        puts "Unused resource strings were detected:"
        display_abandoned_identifiers_in_map(map)
    end
else
    puts "Please provide the root and generated files directories for source code files as a command line argument."
end
