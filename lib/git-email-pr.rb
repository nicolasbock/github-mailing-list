require "octokit"
require "optparse"
require "pp"
require "tmpdir"

class GitHubMailingList

  attr_reader :options

  def initialize(argv)
    OptionParser.new do |opts|
      opts.banner = "Usage: send-pr [options] USER REPOSITORY N"

      @verbose = false
      opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
        @verbose = v
      end

      opts.on("-t", "--to EMAIL", "Email recipient") do |n|
        @to = n
      end

      opts.on("-f", "--from EMAIL", "Send email from this address") do |f|
        @from = f
      end

      opts.on("--reply-to EMAIL", "The reply-to address") do |r|
        @reply_to = r
      end

      opts.on("-r", "--repo USER/REPOSITORY", "The repository as USER/REPOSITORY") do |r|
        @repo = r
      end

      opts.on("-N", "--number N", "Pull request number") do |n|
        @number = n
      end

      @workdir = "/var/tmp/git-email-pr"
      @patch_dir = "patches"
      opts.on("-d", "--workdir", "The workdir") do |d|
        @workdir = d
      end
    end.parse! argv.dup

    raise OptionParser::ParseError, "missing --repo" if @repo.nil?
    raise OptionParser::ParseError, "missing --number" if @number.nil?
    raise OptionParser::ParseError, "missing --to" if @to.nil?

    @access_token = ENV['GITHUB_TOKEN']
    raise OptionParser::ParseError, "You must export GITHUB_TOKEN" if @access_token.nil?
  end

  def fetch
    @client = Octokit::Client.new(:access_token => @access_token)
    @pr = @client.pull_request(@repo, @number)
    @review_comments = @client.pull_request_comments(@repo, @number)
    @issue_comments = @client.issue_comments(@repo, @number)

    if @verbose
      puts "Pull Request:"
      p @pr

      puts "Comments (#{@issue_comments.size}):"
      p @issue_comments

      puts "Review comments (#{@review_comments.size}):"
      p @review_comments
    end
  end

  def parse_msg_id
    @msg_id = nil
    @reroll_count = 0
    @issue_comments.each do |c|
      result = /Message-Id: <+([^<>]+)>/.match(c[:body])
      if not result.nil?
        @msg_id = result[1]
        puts "msg_id = #{@msg_id}"
      end
      result = /count: ([0-9]+)/.match(c[:body])
      if not result.nil?
        @reroll_count = result[1].to_i
      end
    end
  end

  def clone_PR
    Dir.mkdir(@workdir) unless Dir.exist?(@workdir)
    Dir.chdir(@workdir) do
      puts `git clone #{@pr[:base][:repo][:clone_url]} #{@pr[:base][:repo][:ref]}`
    end
  end

  def checkout_PR
    Dir.chdir(@workdir) do
      Dir.chdir(@pr[:base][:repo][:name]) do
        if @from.nil?
          user_name = `git config --get user.name`.strip
          user_email = `git config --get user.email`.strip

          if not user_email.empty? and not user_name.empty?
            @from = "#{user_name} <#{user_email}>"
            if @verbose
              puts "from set to #{@from}"
            end
          end
        end

        puts `git fetch origin +refs/pull/#{@number}/head`
        puts `git checkout FETCH_HEAD`
      end
    end
  end

  def create_patches
    Dir.chdir(@workdir) do
      @patch_dir = File.join(@workdir, @patch_dir)
      Dir.mkdir(@patch_dir) unless Dir.exists?(@patch_dir)
      Dir.chdir(@pr[:base][:repo][:name]) do
        @reroll_count += 1

        @cover_letter = "0000-cover-letter.patch"

        args = []
        args << "--cover-letter"
        #args << "--subject-prefix='PATCH #{repo} #{pr[:base][:ref]}'"
        args << "--output-directory" << @patch_dir
        args << "--thread=shallow"
        if not @msg_id.nil?
          args << "--in-reply-to=#{@msg_id}"
          args << "--reroll-count" << @reroll_count
          options[:cover_letter] = "v#{@reroll_count}-" + @cover_letter
        end
        args << "origin/#{@pr[:base][:ref]}"

        if @verbose
          puts "cover_letter = #{@cover_letter}"
          puts "args = #{args.join(' ')}"
        end
        puts `git format-patch #{args.join(" ")}`
      end
    end
  end

  def fix_coverletter
    Dir.chdir(@workdir) do
      Dir.chdir(@pr[:base][:repo][:name]) do
        text = File.read(File.join(@patch_dir, @cover_letter))
        if @msg_id.nil?
          @msg_id = /Message-Id: (.*)/.match(text)[1]
        end
        if @verbose
          puts "new Message-Id: #{@msg_id}"
        end

        @note = "This pull request has been submitted to " +
          @to + " as Message-Id: #{@msg_id}, count: #{@reroll_count}"

        text.gsub!(/[*]{3} SUBJECT HERE [*]{3}/, @pr[:title])
        text.gsub!(/[*]{3} BLURB HERE [*]{3}/, @note + "\n\n" +
                   "Repository: #{@repo} #{@pr[:base][:ref]}\n" +
                   "URL: #{@pr[:base][:repo][:clone_url]}\n" +
                   "     #{@pr[:base][:repo][:ssh_url]}\n\n" +
                   @pr[:body])
        File.open(File.join(@patch_dir, @cover_letter), "w") do |f|
          f.puts text
        end

        if @verbose
          puts `cat #{File.join(@patch_dir, @cover_letter)}`
        end
      end
    end
  end

  def send_email
    Dir.chdir(@workdir) do
      Dir.chdir(@pr[:base][:repo][:name]) do
        args = []
        args << "--no-thread"
        args << "--confirm never"
        args << "--to=\"#{@to}\""
        args << "--from=\"#{@from}\"" unless @from.nil?
        args << "--suppress-cc=author"
        args << "#{@patch_dir}"
        if @verbose
          puts "running git send-email #{args.join(' ')}"
        end
        #puts `git send-email #{args.join(" ")}`
      end
    end
  end

  def leave_comment
    #client.add_comment(@repo, @number, @note)
  end

end
