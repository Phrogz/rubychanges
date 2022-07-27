DBFILE = 'database.yaml'
BASE_RELEASE = 2.3

def run!
	changes = changes_from_db
	known_releases = changes.map(&:release).uniq.map(&:to_f).sort.unshift(BASE_RELEASE)
	options = fetch_options(known_releases)
	changes = filter_changes(changes:, options:)
	create_report(changes, known_releases, options)
end

def changes_from_db
	require_relative './change'
	require 'yaml'
	YAML.load(
		File.open(DBFILE, "r:utf-8", &:read),
		permitted_classes: [Change, Change::RubyIssue, Change::GitHubPullRequest]
	)
end

def fetch_options(known_releases)
	require 'optparse'
	Struct.new(:from, :to, :group_by_class, :breaking_only, :language_only, :level, :verbose, :file).new.tap do |opts|
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
			op.on('-l', '--language-only', 'Show only changes to the language (not specific classes/methods)') do
				opts.language_only = true
			end
			op.on('-i', '--important', 'Show only the most important changes') do
				opts.level = 3
			end
			op.on('-r', '--relevant', 'Show only major/medium changes (ignore esoteric changes)') do
				opts.level = 2
			end
			op.on('-o changes.html', '--output changes.html', "Set the output filename (default: #{opts.file})") do |f|
				opts.file = f
			end
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

def filter_changes(changes:, options:)
	# changes = changes.filter{ |c| c.release > options.from && c.release <= options.to && c.level >= options.level }
	if options.breaking_only
		changes = changes.filter{ |c| c.kind=='removal' || c.kind=='change' }
	end
	allowed_sections = [Change::SECTION_LANGUAGE]
	allowed_sections << Change::SECTION_CORE unless options.language_only
	changes = changes.filter{ |c| allowed_sections.include?(c.section) }
	changes
end

def create_report(changes, known_releases, options)
	require 'kramdown'
	require 'kramdown-parser-gfm'
	require 'nokogiri'
	require 'json'
	releases = known_releases.filter{ _1 > options.from && _1 <= options.to }
	adjectives = []
	adjectives << 'Important' if options.level==3
	adjectives << 'Non-Esoteric' if options.level==2
	adjectives << 'Potentially-Breaking' if options.breaking_only
	by_section = changes.group_by{ _1.section }

	md2html = ->(md) { Kramdown::Document.new(md, input:'GFM').to_html.gsub(/\A<p>|<\/p>\Z/,'').strip }
	md2text = ->(md) { Nokogiri::HTML(md2html[md]).text.gsub(/\n+ */, '&#10;') }

	change_summary = ->(c) {
		"<p class='#{c.kind}' title='#{md2text[c.summary].gsub("'", '&apos;')}'>#{md2html[c.title]}</p>"
	}

	File.open(options.file, 'w:utf-8') do |f|
		f << <<~PREAMBLE
			<!DOCTYPE html>
			<html>
			<head>
				<meta charset="utf-8"><title>Changes to Ruby</title>
				<style>
					body { background:white; font-family:Tahoma, Calibri, 'Trebuchet MS' }
					td { vertical-align:top; color:#333 }
					code { color:#369; font-size:1.2em }

					.addition::before, .removal::before, .change::before, .promotion::before, .deprecation::before { font-family:monospace; vertical-align:middle; line-height:1em; display:inline-block; padding-right:0.1em; font-size:1.6em }
					.addition::before { content:'⊕'; color:#060 }
					.promotion::before { content:'✪'; color:#0c0 }
					.deprecation::before { content:'⎊'; color:#900 }
					.removal::before { content:'⊗'; color:#c00 }
					.change::before { content:'⊛'; color:orange }

					table { margin:1em auto; border-spacing:1em }
					caption { color:black; font-weight:bold; padding-bottom:0.6em; white-space:nowrap }
					th { border-bottom:1px solid #ccc }
					p { margin:0; margin-bottom:0.5em; font-size:0.85em }
					th.release { vertical-align:middle; text-align:center; border-bottom:none; border-right:1px solid #ccc }
					th.release span { -ms-writing-mode:tb-rl; -webkit-writing-mode:vertical-rl; writing-mode:vertical-rl; transform:rotate(180deg)	}
				</style>
			</head><body>
			<table><caption>
				<span id="changecount"></span>
				<select id="changefilter">
					<option value="highlights">Highlighted</option>
					<option value="breakingonly">Potentially-Breaking</option>
					<option value="medium">Non-Esoteric</option>
					<option value="" selected></option>
				</select>
				Changes to Ruby
				<select id="languageonly">
					<option value="1">Language &amp; Core</option>
					<option value="0">Language Only</option>
				</select>
				between
				<select id="relfrom">#{known_releases[0..-2].map{"<option>#{_1}</option>"}}</select>
				and
				<select id="relto">#{known_releases[1..-1].map{"<option#{' selected' if _1 == known_releases.last}>#{_1}</option>"}}</select>
			</caption><thead><tr><td></td>
				#{by_section.keys.map{ "<th>#{_1}</th>" }.join}
			</tr></thead><tbody>
		PREAMBLE
		releases.each do |release|
			f << "<tr data-release='#{release}'><th class='release'><span>#{release}</span></th>"
			by_section.keys.each{ f << "<td data-islang='#{_1 == Change::SECTION_LANGUAGE ? 0 : 1}' data-section='#{_1}'></td>" }
			f << "</tr>\n"
		end
		f << "</tbody></table>"
		f << <<~ENDSCRIPT
		<script>
			const tmpEl = document.createElement('div');
			$releases = #{known_releases.to_json};
			$changes = #{changes.to_h{ [_1.unique_id, _1.to_h]}.to_json};

			Array
			.from(document.querySelectorAll('select'))
			.forEach( sel => sel.addEventListener('change', filter, false));

			filter();

			function filter(){
				Array
				.from(document.querySelectorAll('tbody td'))
				.forEach( td => td.innerHTML = '');

				const releasesToShow = $releases.filter( r => {
					return r > relfrom.value*1 && r <= relto.value*1;
				});

				let changeCount = 0;
				Array
				.from(document.querySelectorAll('tbody tr'))
				.forEach( tr => {
					const release = tr.dataset.release*1;
					const showRelease = releasesToShow.includes(release);
					tr.style.display = showRelease ? '' : 'none';
					let changesSoFar = changeCount;
					if (showRelease) {
						Array
						.from(tr.querySelectorAll('td'))
						.forEach( td => {
							const section = td.dataset.section;
							const showSection = td.dataset.islang*1 <= languageonly.value*1;
							td.style.display = showSection ? '' : 'none';
							if (showSection) {
								changeCount += addSummariesFor(release, section, td);
							}
						});
					}
					if (changeCount == changesSoFar) {
						// We did not get any changes for this release, hide it
						tr.style.display = 'none';
					}
				});
				changecount.innerHTML = changeCount;
			}

			function addSummariesFor(release, section, el) {
				return Object.entries($changes)
					.filter( ([_,c]) => c.release==release && c.section==section )
					.filter( ([_,c]) => {
						switch(changefilter.value) {
							case 'breakingonly':
								return c.kind=='removal' || c.kind=='change';
							case 'highlights':
								return c.level==3;
							case 'medium':
								return c.level>=2;
							default:
								return true;
						}
					})
					.sort( ([id1,a],[id2,b]) => (a.level==b.level) ? (a.scope < b.scope ? -1 : a.scope > b.scope ? 1 : 0) : b.level-a.level )
					.map( ([id, c]) => {
						const node = el.appendChild(document.createElement('p'));
						node.innerHTML = c.title;
						if (c.brief) node.title = t(c.brief);
						if (c.kind) node.className = c.kind;
					})
					.length;
			}

			function t(html) {
				tmpEl.innerHTML = html;
				return tmpEl.innerText;
			}
		</script></body></html>
		ENDSCRIPT
	end
end

run! if __FILE__==$0

__END__
