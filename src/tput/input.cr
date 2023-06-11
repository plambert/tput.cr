class Tput
  class KeyInput
    property char : Char? = nil
    property key : Key? = nil
    property sequence : Array(Char) = [] of Char
    @end_of_input : Bool = false

    def initialize(*, @char = nil, @key = nil)
      if c = @char
        @sequence << c
      end
    end

    def finish
      @end_of_input = true
    end

    def continue?
      !@end_of_input
    end

    def <<(c : Char?)
      @sequence << c if c
    end

    def key_or_char
      @key || @char
    end

    def clear
      @sequence.clear
    end

    def to_s(io)
      io << "KeyInput["
      if k = @key
        k.to_s(io)
      elsif c = @char
        c.to_s(io)
      else
        io << "NIL"
      end
      @sequence.to_s(io)
      if @end_of_input
        io << "(END)"
      end
      io << ']'
    end
  end

  module Input
    include Crystallabs::Helpers::Logging

    # Enables synced (unbuffered) output for the duration of the block.
    def with_sync_output
      output = @output
      if output.is_a?(IO::Buffered)
        before = output.sync?

        begin
          output.sync = true
          yield
        ensure
          output.sync = before
        end
      else
        yield
      end
    end

    # Enables raw (unbuffered, non-cooked) input for the duration of the block.
    def with_raw_input
      input = @input
      if @mode.nil? && input.responds_to?(:fd) && input.tty?
        preserving_tc_mode(input.fd) do |mode|
          raw_from_tc_mode!(input.fd, mode)
          yield
        end
      else
        yield
      end
    end

    # Copied from IO::FileDescriptor, as this method is sadly `private`.
    private def raw_from_tc_mode!(fd, mode)
      LibC.cfmakeraw(pointerof(mode))
      LibC.tcsetattr(fd, Termios::LineControl::TCSANOW, pointerof(mode))
    end

    # Copied from IO::FileDescriptor, as this method is sadly `private`.
    private def preserving_tc_mode(fd)
      if LibC.tcgetattr(fd, out mode) != 0
        raise RuntimeError.from_errno("Failed to enable raw mode on output")
      end

      before = mode
      @mode = mode

      begin
        yield mode
      ensure
        @mode = nil
        LibC.tcsetattr(fd, Termios::LineControl::TCSANOW, pointerof(before))
      end
    end

    def next_char(timeout : Bool = false)
      input = @input

      if timeout && input.responds_to? :"read_timeout="
        input.read_timeout = @read_timeout
      end

      begin
        c = input.read_char
      rescue IO::TimeoutError
        c = nil
      end

      if timeout && input.responds_to? :"read_timeout="
        input.read_timeout = nil
      end

      c
    end

    def next_char(timeout : Bool = false, &)
      if c = next_char(timeout)
        yield c
      end
      c
    end

    # def next_key
    #   with_raw_input do
    #     sequence = [] of Char
    #     while char = next_char { sequence }
    # end

    def listen(&block : Proc(KeyInput, Nil))
      with_raw_input do
        while char = next_char
          keyinput = KeyInput.new char: char
          if keyinput.control?
            keyinput.key = Key.read_control(char) { next_char(true) { |c| keyinput << c } }
          end
          begin
            yield keyinput
          rescue e : EndListen
            keyinput.finish
          end
          break unless keyinput.continue?
          keyinput.clear
        end
      end
    end

    # def listen(&block : Proc(Char, Key?, Array(Char), Nil))
    #   listen do |keyinput|
    #     yield keyinput.char, keyinput.key, keyinput.sequence
    #   end
    # end

    # def listen(&block : Proc(Char, Key?, Array(Char), Nil))
    #   with_raw_input do
    #     sequence = [] of Char
    #     while char = next_char
    #       sequence << char if char
    #       key = nil
    #       if char.control?
    #         key = Key.read_control(char) { next_char(true) { |c| sequence << c } }
    #       end
    #       begin
    #         yield char, key, sequence.dup
    #       rescue e : EndListen
    #         break
    #       end
    #       sequence.clear
    #     end
    #   end
    # end
  end
end
