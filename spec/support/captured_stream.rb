# frozen_string_literal: true

require "stringio"

# A standard stream captured for an assertion.
#
# TTY::Screen asks $stdout, $stdin and $stderr for the terminal width with
# `ioctl` and rescues only SystemCallError, so a bare StringIO standing in for
# one of them raises NoMethodError from inside the box drawing code instead of
# falling back to a default width. A captured stream is a closed terminal, so
# it answers like one.
class CapturedStream < StringIO
  def ioctl(*) = raise(Errno::ENOTTY)
end
