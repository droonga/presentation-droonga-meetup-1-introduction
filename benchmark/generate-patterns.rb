require "json"

body = JSON.parse(STDIN.read).last.last
records = body[2..-1]
$with_query_patterns = records.collect do |record|
  title = record.first
  query = title.gsub(/[:;]/, " ")
               .strip
               .gsub(/ +/, "%20")
  {
    "path" => "/d/select?query=#{query}&table=Pages&limit=50&match_columns=title,text&output_columns=snippet_html(title),snippet_html(text),categories,_key&drilldown=categories&drilldown_limits=50&drilldown_sortby=-_nsubrecs"
  }
end

def add_patterns(patterns, host=nil, frequency=1.0)
  suffix = ""
  suffix = "-#{host}" unless host.nil?

  patterns["with-query#{suffix}"] = {
    "frequency" => frequency / 2.0,
    "method"    => "get",
    "patterns"  => $with_query_patterns
  }

  patterns["without-query#{suffix}"] = {
    "frequency" => frequency / 2.0,
    "method"    => "get",
    "patterns"  => [
      {
        "path" => "/d/select?table=Pages&limit=50&output_columns=title,categories,_key&drilldown=categories&d rilldown_limits =50&drilldown_sortby=-_nsubrecs"
      }
    ]
  }

  if host
    patterns["with-query#{suffix}"]["host"] = host
    patterns["without-query#{suffix}"]["host"] = host
  end

  patterns
end

patterns = {}

hosts=ARGV.first
if hosts.is_a?(String)
  hosts = hosts.split(/\s*,\s*/)
  hosts.each do |host|
    add_patterns(patterns, host, 1.0 / hosts.size)
  end
else
  add_patterns(patterns)
end

puts JSON.pretty_generate(patterns)
