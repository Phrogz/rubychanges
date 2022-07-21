require 'yaml'
DBFILE = 'database.yaml'

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

	attr_accessor :title, :summary, :kind, :code, :notes, :reason, :followup, :highlight, :version, :section, :category
	attr_reader :disussion, :docs, :classes
	def initialize(hash, extras={})
		@discussion = []
		@docs = []
		@classes = []
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

end

def run!
	changes = changes_from_db
	p "#{changes.length} changes"
end

def changes_from_db
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


run! if __FILE__==$0