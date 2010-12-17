#!/usr/bin/ruby
# Simple DSP-420 LCD Ruby Class.

require 'rubygems'
require 'serialport'
require 'socket'

class DSP420
  def initialize(port = "/dev/ttyUSB0")
    @sp = SerialPort.new port, 9600
    @sp.flow_control = SerialPort::NONE
  end

  def hexctl(i)
    # converts an integer between 1 and 40 to its hex control character.
    "0x#{(i + 48).to_s(16)}".hex.chr
  end

  def clear(start_pos=1, end_pos=40)
    # Clears (C) all characters from start_pos to end_pos
    @sp.write 0x04.chr + 0x01.chr +
              "C" + hexctl(start_pos) + hexctl(end_pos) + 0x17.chr
  end

  def set_cursor(pos)
    # Sets cursor pos (P) to position 'pos' (between 1 and 40)
    @sp.write 0x04.chr + 0x01.chr + "P" + hexctl(pos) + 0x17.chr
  end

  def write(string, min = 1, max = 40, pre_clear = true)
    string = string[0, (max-min+1)]
    # Writes string to LCD.
    # The pre_clear var is a hack to fix a timing bug due to setting the cursor and then
    # writing data. It fixed the time not being displayed properly.
    clear(min, max) if pre_clear
    set_cursor(min)
    sleep 0.1 unless pre_clear
    @sp.write string
  end

  def center(str, length)
    # if a string is less than the max length, it pads spaces at the left to center it.
    if str.size < length
      lpad = ((length - str.size) / 2).to_i
      return " " * lpad + str
    end
    str
  end

  def format_time(t)
    min, sec = (t.to_i / 60), (t.to_i % 60)
    min, sec = 0, 0 if min < 0
    time = "%02d:%02d" % [min, sec]
  end

  # A user input prompt on LCD screen, with cursor and backspace/del keys, and ESC to cancel.
  # Prompt can be displayed to edit an existing string.
  # View port is also scrolled to keep up with cursor, but does not move unless it needs to.
  # Requires 'curses' library.
  def lcd_prompt(title, value="", cursor=0, view_start=0)
    write title.ljust(20), 1, 20
    #puts title.ljust(20)

    # Returns string to the method caller when the enter key is pressed.
    # Returns empty string if escape key is pressed.
    while true
      prompt_str = "? " + (cursor > 0 ? value[0..(cursor-1)] : '') + "_" + value[(cursor+1)..-1].to_s

      view_start = 0 if prompt_str.size <= 20
      # Allows a buffer of 20 characters for the cursor to move left and right without altering the view.
      prompt_str = prompt_str[view_start, 20]

      write prompt_str, 21, 40
      #print "\r" + prompt_str

      # Wait for keypresses
      key = getch
      case key
      when Key::LEFT
        cursor -= 1
        view_start = (cursor+2) if (cursor+2) < view_start
      when Key::RIGHT
        cursor += 1
        view_start += 1 if (cursor+1) >= (view_start + 20)
      when 10 # Key::ENTER
        return value
      when Key::BACKSPACE
        value = (cursor-2 >= 0 ? value[0..(cursor-2)] : "") + value[(cursor)..-1].to_s if cursor > 0
        cursor -= 1
        view_start = (cursor+2) if (cursor+2) < view_start
      when Key::DC
        value = (cursor-1 >= 0 ? value[0..(cursor-1)] : "") + value[(cursor+1)..-1].to_s if cursor < value.size
      when 27 # ESC
        return ""
      else
        if key <= 128 && key >= 32
          value = (cursor-1 >= 0 ? value[0..(cursor-1)] : "") + key.chr + value[(cursor)..-1].to_s if cursor >= 0
          cursor += 1
          view_start += 1 if (cursor+2) >= (view_start + 20)
        end
      end

      cursor = value.size if cursor >= value.size
      if cursor <= 0
        cursor, view_start = 0, 0
      end
    end
  end

  def spinner(pos=20, interval=0.1)
    return Thread.new do
      while true
        write '\\', pos,pos, false
        sleep interval
        write "|", pos,pos, false
        sleep interval
        write "/", pos,pos, false
        sleep interval
        write "-", pos,pos, false
        sleep interval
      end
    end
  end
end

# Widget class to display blocks of text at arbitrary positions, with scrolling.
class Widget
  attr_accessor :pos, :length, :scroll_pos, :needs_refresh
  attr_reader :value

  def initialize(value, pos, length=20, format=:none, align=:ljust)
    raise "Invalid 'align' param!" unless [:ljust, :rjust, :center].include?(align)
    @value, @pos, @length, @format, @align = value, pos, length, format, align
    @scroll_pos = 1
    # After widget is first initialized, it needs to be displayed.
    @needs_refresh = true
  end

  def value=(value)
    # If we are setting the widget string, the display needs to be refreshed.
    @value = value
    @needs_refresh = true
  end

  def padded(str)
    # Give the string a buffer padding of 2 spaces on either side, if we are going to scroll it.
    "  #{str}  "
  end
  def format_as_time(str)
    min, sec = (str.to_i / 60), (str.to_i % 60)
    min, sec = 0, 0 if min < 0
    time = "%02d:%02d" % [min, sec]
  end

  def increment_scroll
    # Only increment the scroll pos if we need to.
    if @value.size > @length
      @scroll_pos += 1
      @scroll_pos = 1 if padded(@value)[@scroll_pos-1, padded(@value).size].size < @length
      @needs_refresh = true    # need to refresh display.
      true
    end
  end

  def render
    # If we are rendering, it means we no longer need to refresh.
    @needs_refresh = false

    string = case @format
    when :time
      format_as_time(@value)
    else
      @value
    end

    # Returns the display string for the widget - padded and scrolled.
    if string.size > @length
      padded(string)[@scroll_pos-1, @length]
    else
      string.send(@align, @length)
    end
  end

end

