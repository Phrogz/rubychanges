DBFILE = 'database.yaml'
BASE_RELEASE = 2.7

def run!
	changes = changes_from_db
	known_releases = changes.map(&:release).uniq.map(&:to_f).sort.unshift(BASE_RELEASE)
	options = fetch_options(known_releases)

	changes = changes.filter{ |c| c.release > options.from && c.release <= options.to && c.level >= options.level }
	if options.breaking_only
		changes = changes.filter{ |c| c.kind=='removal' || c.kind=='change' }
	end


	create_report(changes, known_releases, options)
end

def changes_from_db
	require 'yaml'
	YAML.load(File.open(DBFILE, "r:utf-8", &:read))
	.then do |hierarchy|
		hierarchy.flat_map do |release|
			version = nil
			release.flat_map do |section, changes|
				if section=='version'
					version = changes
					nil
				else
					changes.map{ |c| Change.new(c, version:, section:) }
				end
			end
		end
	end
	.compact
end

def fetch_options(known_releases)
	require 'optparse'
	Struct.new(:from, :to, :group_by_class, :breaking_only, :level, :verbose, :file).new.tap do |opts|
		opts.level = 1
		opts.group_by_class = false
		opts.from = BASE_RELEASE
		opts.to = known_releases.last
		opts.file = 'ruby-changes.html'
		OptionParser.new do |op|
			op.banner = "Usage: ruby distill.rb [options]"
			op.on('-h', '--help', 'Prints this help') do
				puts op
				exit
			end
			op.on('-r', '--releases', 'Show a list of documented releases') do
				puts "Documented releases: #{known_releases.join(', ')}"
			end
			op.on("-f #{opts.from}", "--from #{opts.from}", "Show only changes after this release (default: #{opts.from})") do |v|
				opts.from = v.to_f
			end
			op.on("-t #{opts.to}", "--to #{opts.to}", "Show only changes up to and including this release (default: #{opts.to})") do |v|
				opts.to = v.to_f
			end
			op.on('-v', '--verbose', 'Show debugging output during run') do |v|
				opts.verbose = true
			end
			op.on('-b', '--breaking-only', 'Show only changes that modify the way the language works, potentially affecting existing scripts') do
				opts.breaking_only = true
			end
			op.on('-i', '--important', 'Show only the most important changes') do
				opts.level = 3
			end
			op.on('-r', '--relevant', 'Show only major/medium changes (ignore esoteric changes)') do
				opts.level = 2
			end
			op.on('-o changes.html', '--output changes.html', "Set the output filename (default: #{opts.file})")
		end.parse!
		puts opts if opts.verbose

		unless known_releases.include?(opts.from)
			warn "Unsupported release #{opts.from}; must be one of: #{known_releases.inspect}"
			exit
		end

		unless known_releases.include?(opts.to)
			warn "Unsupported release #{opts.to}; must be one of: #{known_releases.inspect}"
			exit
		end
	end
end

def create_report(changes, known_releases, options)
	require 'kramdown'
	require 'nokogiri'
	releases = known_releases.filter{ _1 > options.from && _1 <= options.to }
	adjectives = []
	adjectives << 'Important' if options.level==3
	adjectives << 'Non-Esoteric' if options.level==2
	adjectives << 'Potentially-Breaking' if options.breaking_only
	title = "#{changes.length} #{adjectives.join(', ')} Change#{:s unless changes.length==1} to Ruby from #{options.from} to #{options.to}"
	by_section = changes.group_by{ _1.section }

	md2html = ->(md) { Kramdown::Document.new(md).to_html.gsub(/\A<p>|<\/p>\Z/,'').strip }
	md2text = ->(md) { Nokogiri::HTML(md2html[md]).text.gsub(/\n+ */, '&#10;') }

	change_summary = ->(c) {
		"<p class='#{c.kind}' title='#{md2text[c.summary].gsub("'", '&apos;')}'>#{md2html[c.title]}</p>"
	}

	File.open(options.file, 'w:utf-8') do |f|
		f << <<~PREAMBLE
			<!DOCTYPE html>
			<html>
			<head>
				<meta charset="utf-8"><title>#{title}</title>
				<style>
					body { background:white; font-family:Tahoma, Calibri, 'Trebuchet MS' }
					td { vertical-align:top; color:#333 }
					code { color:#369 }

					.addition::before, .removal::before, .change::before, .promotion::before, .deprecation::before { font-family:monospace; vertical-align:middle; line-height:1em; display:inline-block; padding-right:0.1em; font-size:1.6em }
					.addition::before { content:'⊕'; color:#060 }
					.promotion::before { content:'✪'; color:#0c0 }
					.deprecation::before { content:'⎊'; color:#900 }
					.removal::before { content:'⊗'; color:#c00 }
					.change::before { content:'⊛'; color:orange }

					table { margin:1em auto; border-spacing:1em }
					caption { color:black; font-weight:bold; padding-bottom:0.6em }
					th { border-bottom:1px solid #ccc }
					p { margin:0; margin-bottom:0.5em; font-size:0.85em }
					th.release { vertical-align:middle; text-align:center; border-bottom:none; border-right:1px solid #ccc }
					th.release span { -ms-writing-mode:tb-rl; -webkit-writing-mode:vertical-rl; writing-mode:vertical-rl; transform:rotate(180deg)	}
				</style>
			</head><body>
			<table><caption>#{title}</caption><thead><tr><td></td>
				#{by_section.keys.map{ "<th>#{_1}</th>" }.join}
			</tr></thead><tbody>
		PREAMBLE
		releases.each do |release|
			f << "<tr><th class='release'><span>#{release}</span></th>"
			by_section.each do |_,changes|
				f << '<td>'
				changes.filter{ _1.release==release }.each do |change|
					f << change_summary[change] << "\n"
				end
				f << '</td>'
			end
			f << "</tr>\n"
		end
		f << '</tbody></table></body></html>'
	end
end

class Change
	class Discussion
		attr_accessor :label, :url
		def to_s
			self.label.to_s
		end
		def to_html
			"<a href='#{self.url}'>#{self.label}</a>"
		end
	end
	class RubyIssue < Discussion
		def initialize(type, id)
			self.label = "#{@type} ##{@id}"
			self.url = "https://bugs.ruby-lang.org/issues/#{@id}"
		end
	end
	class GitHubPullRequest < Discussion
		def initialize(id)
			self.label = "GH-##{@id}"
			self.url = "https://github.com/ruby/ruby/pull/#{@id}"
		end
	end

	class DocLink
		def initialize(url)
			@url = url
		end
		def title
			"TODO: fetch html title"
		end
		def to_html
			"<a href='#{@url}'>#{self.title}</a>"
		end
	end

	attr_accessor :title, :summary, :kind, :code, :notes, :reason, :followup, :highlight, :section, :category
	attr_reader :disussion, :docs, :classes, :release, :level
	def initialize(hash, extras={})
		@discussion = []
		@docs = []
		@classes = []
		@level = 2
		@summary = ''
		hash.merge(extras).each{ |k,v| self.send(:"#{k}=", v)}
	end
	def feature=(o)
		@discussion.push(*[*o].map{ RubyIssue.new('Feature', _1) })
	end
	def bug=(o)
		@discussion.push(*[*o].map{ RubyIssue.new('Bug', _1) })
	end
	def docs=(o)
		@docs = [*o].map{ DocLink.new(_1) }
	end
	def class=(o)
		@classes = [*o]
	end

	define_method(:"github-pull-request=") do |o|
		@discussion.push(*[*o].map{ GitHubPullRequest.new(_1) })
	end

	def version=(v)
		@release = v.to_f
	end
	def importance=(v)
		@level = case v
			when 'important', 'high'; 3
			when 'medium'; 2
			when 'low'; 1
			else
				warn "Unrecognized importance level #{v}"
		end
	end


end

run! if __FILE__==$0

__END__
