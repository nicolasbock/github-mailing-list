require "optparse"

class ParseCommandLine
  def initialize(argv)
    options = {}
    OptionParser.new do |opts|
      opts.banner = "Usage: send-pr [options] USER REPOSITORY N"

      options[:verbose] = false
      opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
        options[:verbose] = v
      end

      opts.on("-t", "--to EMAIL", "Email recipient") do |n|
        options[:to] = n
      end

      opts.on("-f", "--from EMAIL", "Send email from this address") do |f|
        options[:from] = f
      end

      opts.on("--reply-to EMAIL", "The reply-to address") do |r|
        options[:reply_to] = r
      end

      opts.on("-u", "--user USER", "Github user or organization") do |u|
        options[:user] = u
      end

      opts.on("-r", "--repository REPOSITORY", "The name of the repository") do |r|
        options[:repository] = r
      end

      opts.on("-N", "--number N", "Pull request number") do |n|
        options[:number] = n
      end

      opts.on("-l", "--list-PRs", "List pull requests") do |l|
        options[:list] = true
      end
    end.parse! argv

    raise OptionParser::ParseError, "missing --user" if options[:user].nil?
    raise OptionParser::ParseError, "missing --repository" if options[:repository].nil?
    raise OptionParser::ParseError, "missing --number" if options[:number].nil?
    raise OptionParser::ParseError, "missing --to" if options[:to].nil?

    options[:access_token] = ENV['GITHUB_TOKEN']
    raise OptionParser::ParseError, "You must export GITHUB_TOKEN" if options[:access_token].nil?

    options
  end
end
