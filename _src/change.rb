class Change
    SECTION_LANGUAGE = "Language Changes"
    SECTION_CORE = "Core Classes and Modules"
    SECTION_STDLIB = "Standard Library"
	class Discussion
		attr_accessor :label, :url, :comments
		def to_s
			self.label.to_s
		end
        def to_h
            {label:,url:,comments:}.compact
        end
		def to_html
			"<a href='#{self.url}'>#{self.label}</a> #{self.comments}"
		end
	end

	class RubyIssue < Discussion
		def initialize(type, id, comments)
			self.label = "#{type} ##{id}"
			self.url = "https://bugs.ruby-lang.org/issues/#{id}"
            self.comments = comments
		end
	end

	class GitHubPullRequest < Discussion
		def initialize(id)
			self.label = "GH-##{@id}"
			self.url = "https://github.com/ruby/ruby/pull/#{@id}"
		end
	end

	attr_accessor :release, :title, :summary, :kind, :notes, :reason, :followup, :highlight, :section, :path, :affects, :scope
	attr_reader :discussion, :classes, :level

    alias_method :note=, :notes=
    alias_method :notice=, :notes=
    alias_method :"follow-up=", :followup=
    alias_method :"follow-ups=", :followup=
    alias_method :"reason/usage=", :reason=

    def initialize(hash={}, extras={})
		@level = 2
        @scope = ''
		hash.merge(extras).each{ |k,v| self.send(:"#{k}=", v)}
    end

    def class=(o)
		@classes = [*o]
	end

    def discussion=(prose)
        @discussion ||= []
        prose.scan(/\[(Feature|Bug) #(\d+)\]\(.+?\)(?: \(([^)]+)\))?/) do |kind, id, note|
            @discussion << RubyIssue.new(kind, id, note)
        end
        prose.scan(/\[GH-(\d+)\]/) do |id|
            @discussion << GitHubPullRequest.new(id)
        end
    end
    alias_method :discussions=, :discussion=

    def documentation=(prose)
        (@docs ||= []) << prose
    end

    def documentation
        @docs && @docs.join("\n")
    end

	def importance=(v)
		@level = case v
			when 'important', 'high', 'highlight'; 3
			when 'medium'; 2
			when 'low'; 1
			else
				warn "Unrecognized importance level #{v}"
		end
	end

    def metadata=(v)
        v.scan(/(\w+):(.+?)(?=, |\})/) do |k, v|
            self.send( :"#{k}=", v)
        end
    end

    def affects=(prose)
        (@affects ||= []) << prose
    end
    alias_method :"affected methods=", :affects=
    alias_method :"methods affected=", :affects=
    alias_method :"classes and modules affected=", :affects=
    alias_method :"new and updated methods=", :affects=

    def code=(line)
        if @code || !line.empty?
            (@code ||= []) << line
        end
    end

    def code
        @code && @code.join("\n")
    end

    def unique_id
        [*@path, @title].join(' ').downcase.gsub(/[^\w.]+/, '')
    end

    def md2html(md)
        require 'kramdown'
        require 'kramdown-parser-gfm'
        if md
            Kramdown::Document.new(md, input:'GFM').to_html.gsub(/\A<p>|<\/p>\Z/,'').strip
        end
    end
    def to_h
        {
            release: @release,
            section: @section,
            level:   @level,
            kind:    kind,
            title:   md2html(title),
            brief:   md2html(summary),
            reason:  md2html(reason),
            code:    md2html(code),
            notes:   md2html(notes),
            bg:      discussion && discussion.map(&:to_h),
            docs:    md2html(documentation),
        }.compact
    end
end
