DBFILE = 'database.yaml'
require_relative 'change'
require 'yaml'

def run!
	pull_changes_from_files
		.then{ remove_unwanted _1 }
		.then{ derive_metadata _1 }
		.then{ write_to_database _1 }
end

def pull_changes_from_files
	[].tap do |changes|
		Dir['*.md'].grep(/^\d/).each do |file|
			version = file[/\d\.\d/].to_f
			path = []
			in_comment = false
			change = nil
			last_method = nil
			File.foreach(file).with_index do |line,line_number|
				linedebug = "#{file}##{line_number} | " if $DEBUG
				line.chomp!
				if in_comment
					in_comment = false if line =~ /-->/
				else
					case line
					when /^(#+) ([\w`"].+)/
						# [\w`"] used to avoid summary sections including code block with commented line
						level = $1.length
						path = path[0...level]
						path[level-1] = $2
						changes << (change = Change.new)
						change.title = $2
						change.path = path[0..-2]
						last_method = nil
						puts "#{linedebug}## CREATED issue #{$2.inspect}" if $DEBUG

					when /\* \*\*(.+?):\*\*\s*(?!-$)(.*)/
						method = :"#{$1.downcase}="
						if change.respond_to?(method)
							change.send(method, $2)
							puts "#{linedebug}#{method}#{$2.inspect}" if $DEBUG
							last_method = method unless Change::SINGLE_LINE_FIELDS.include?(method)
						else
							warn "#{linedebug}Skipping unhandled section named #{$1}" if $DEBUG
						end

					when /^<!--.+-->/
						# ignore single-line comments

					when /^<!--/
						in_comment = true

					else
						if last_method
							change.send(last_method, line)
							puts "#{linedebug}#{last_method}#{line.inspect}" if $DEBUG
						elsif change && !line.empty?
							change.summary = line
							puts "#{linedebug}summary=#{line.inspect}" if $DEBUG
						else
							# Ignoring line
						end
					end
				end
			end
		end
	end
end

def derive_metadata(changes)
	changes.each do |c|
		c.path.first[/Ruby (.+)/, 1].then{ c.release = _1 && _1.to_f }
		case c.path[1]
		when /language/i
			c.section = Change::SECTION_LANGUAGE
		when /core/i
			c.section = Change::SECTION_CORE
		when /stdlib/i, /standard library/i
			c.section = Change::SECTION_STDLIB
		when nil
			c.section = c.title.scan(/\w+/).map(&:capitalize).join(' ')
		else
			warn "No idea in what section to put '#{c.path.join('/')}/#{c.title}'."
		end
	end
end

def remove_unwanted(changes)
	changes.reject do |change|
		%i[discussion documentation reason code].all? do |method|
			change.send(method).then{ _1.nil? || _1.empty? }
		end
	end.reject do |change|
		change.path.empty?
	end
end

def write_to_database(changes)
	File.open(DBFILE, 'w:utf-8') do |f|
		f << changes.to_yaml(line_width: -1)
	end
end

run! if __FILE__==$0