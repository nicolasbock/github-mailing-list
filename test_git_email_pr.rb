require "test/unit"
load "git-email-pr"

class TestGitEmailPR < Test::Unit::TestCase

  def test_parse_options()
    assert_raise_with_message(OptionParser::ParseError, "missing --user") do
      parse_options("--help")
    end
  end

end
