require "rubygems"
require "highline/import"
require "rest-client"
require "yaml"
require "optparse"
require "csv"
require "rss"
require "open-uri"
require "reverse-markdown"
require "nokogiri"
require "json"

options = {}

opt_parser = OptionParser.new do |opt|
  opt.banner = "Usage: redmine2github GITHUB_REPO_USER REPO_NAME ISSUE_CSV [OPTIONS]"
  opt.separator ""
  opt.separator "Options"

  opt.on("-n","--dry-run","Not actually write any data to github") do
    options[:dry_run] = true
  end

  opt.on("-u", "--user-file USER_FILE", "Specify YAML file with mapping 'Assignee' to github username") do |user_file|
    options[:user_file] = user_file
  end

  opt.on("-e API_KEY,REDMINE_URL", "--export-comment API_KEY,REDMINE_URL",Array,"Export comments from redmine. API_KEY must be provided. you can find this key when trying to export issues as atom. its the 'key' parameter in the url") do |redmine|
    options[:redmine] = redmine
  end

  opt.on("-m", "--convert-to-markdown", "Convert comment to markdown") do
    options[:convert_markdown] = true
  end
  
  opt.on("-s", "--skip-ssl-cert") do
    OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE
  end

  options[:closed_status_names] = %w(Resolved Feedback Closed)
  opt.on("-c STATUS1,STATUS2,STATUS3,...", "--closed-status-names STATUS1,STATUS2,STATUS3,...",Array,"Specify names of closed statuses, default: #{options[:closed_status_names].join(',')} ") do |closed_status_names|
    options[:closed_status_names] = closed_status_names
  end

  opt.on("-v","--verbose", "Turn on verbose output") do
    options[:verbose] = true
  end
  
  opt.on("-h", "--help", "help") do
    puts opt_parser
    exit
  end


  
end

opt_parser.parse!

# checkout for parameter
if ARGV.size <2
  puts opt_parser
  exit
end

username = ask("Github username: ") {}
puts "empty username" and exit if username.empty?

password = ask("Github password: ") { |q| q.echo = '*' }
puts "empty password" and exit if password.empty?

api_uri = "https://#{username}:#{password}@api.github.com"

puts "Authenticating..."

begin
  res = RestClient.get api_uri 
rescue Exception => e
  puts "Could not connect " + e.message
  exit
end

repo_user = ARGV[0]
repo = ARGV[1]
csv_file = ARGV[2]

if options[:user_file] 
  users = YAML.load_file(options[:user_file])
end

created_label = []

redmine_issues = []

CSV.foreach(csv_file, :headers => true) do |row|
  redmine_issues.push(row)
end

#reverse the order because csv is on LIFO style
redmine_issues.reverse!

redmine_issues.each do |row|
  issue_num = row[0]
  tracker = row['Tracker']
  priority = row['Priority']
  subject = row['Subject']
  assigned_to = row['Assignee']
  description = row['Description']
  status = row['Status']

  # check for exporting commit
  if options[:redmine]
   r = options[:redmine]
   url = "#{r[1]}/issues/show/#{issue_num}?format=atom&key=#{r[0]}"
   
   comments = []
  
   # parse comment
   doc = Nokogiri::XML(open(url))
   doc.css('entry').each do |entry|
     name = entry.at_css("author name").content

     datestr = entry.at_css("updated").content
     date = DateTime.parse(datestr)
     fdate = date.strftime('%a, %d %B %Y %k:%M:%S')

     content = entry.at_css("content")

     if options[:convert_markdown]
      r = ReverseMarkdown.new
      content = r.parse_string(content)        
     end

     comments.push({'name' => name,
       'date' => fdate,
       'content' => content
     })
   end 
  end

  # verbose output
  if options[:verbose]
    puts "Issue #: #{issue_num}"
    puts "Tracker: #{tracker}"
    puts "Priority: #{priority}"
    puts "Subject: #{subject}"
    puts "Assignee: #{assigned_to}"
    puts "Status: #{status}"
    puts "Description: #{description.strip}"
    puts 
    
    if !comments.empty?
      puts "Comments (#{comments.size})"
      puts
      i=0
      comments.each do |comment|
        puts "Comment ##{i=i+1}" 
        puts "author: #{comment['name']}"
        puts "date: #{comment['date']}"
        puts "content: #{comment['content'].strip}"
        puts
      end
    end

    puts
    puts
  end

  # post issue to github
  # process labels
  labels = []
  labels.push("bug") if tracker == "Bug"
  labels.push("enhancement") if tracker == "Feature"
  labels.push("prio-normal") if priority == "Normal"
  labels.push("prio-high") if priority == "High"
  labels.push("prio-urgent") if priority == "Urgent"
  labels.push("prio-immediate") if priority == "Immediate"

  labels.each do |label|
    # create label
    begin
      next if created_label.include?(label)

      label_param = {"name" => label, "color" => ("%06x" % (rand * 0xffffff))}
      res = RestClient.post "#{api_uri}/repos/#{repo_user}/#{repo}/labels", label_param.to_json, :content_type => :json
      created_label.push(label)
    rescue
    end
  end unless options[:dry_run]

  params = {"title" => subject,
    "body" => description.strip,
    "labels" => labels,
  }

  if users && !assigned_to.empty?
    params['assignee'] = users[assigned_to]
  end

  jdata = JSON.generate(params)
  begin
    add_issue_uri = "#{api_uri}/repos/#{repo_user}/#{repo}/issues"
    res = RestClient.post add_issue_uri, jdata, :content_type => :json, :accept => :json

    #get issues number
    github_issue_num = JSON.parse(res)['number']

    #post comment if exists
    if !comments.empty?
      comments.each do |comment|
        body = "Author: #{comment['name']}\n"
        body = body + "Date: #{comment['date']}\n\n"
        body = body + "#{comment['content'].strip}"
        params = {"body" => body}
        comment_uri = "#{api_uri}/repos/#{repo_user}/#{repo}/issues/#{github_issue_num}/comments"
       
        res = RestClient.post comment_uri, params.to_json, :content_type => :json

      end
    end

    # close issue if its status is closed
    if options[:closed_status_names].include? status
      puts "Closing issue..."
      update_issue_uri = "#{api_uri}/repos/#{repo_user}/#{repo}/issues/#{github_issue_num}"
      params = {state: 'closed'}
      res = RestClient.patch update_issue_uri, params.to_json, :content_type => :json, :accept => :json
    end
    
  rescue Exception => e
    puts "Could not connect " + e.message
    puts e.backtrace.join("\n")
    exit
  end unless options[:dry_run]

end

puts "That was a dry run, nothing posted on Github!" if options[:dry_run]
