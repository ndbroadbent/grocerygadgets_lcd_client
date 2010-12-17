#!/usr/bin/env ruby

def relative(filename)
  File.join(File.dirname(__FILE__), filename)
end

require 'rubygems'
require relative('dsp420.rb')

require 'yaml'
require 'net/http'
require 'rexml/document'
require 'uri'

require 'curses'
include Curses
# Capture individual characters from the keyboard.
# ------------------------------------------------------------
crmode
noecho
stdscr.keypad(true)
at_exit { system("stty -raw echo"); stdscr.keypad(false) }

$dsp420 = DSP420.new

# Evo T20 is synced to UTC. HK time is UTC +8
def hk_time
  Time.now + 8*60*60
end
def hk_time_fmt
  hk_time.strftime("%Y-%m-%d %H:%M:%S")
end
def save_barcode_cache
  File.open(relative("config/saved_barcodes.yml"), "w") do |f|
    f.puts $barcode_cache.to_yaml
  end
end

def lcd_puts(str, s_pos=21, e_pos=40)
  $dsp420.write str, s_pos, e_pos
end

def google_base_upc(upc)
  url = URI.parse("http://base.google.com")
  res = Net::HTTP.start(url.host, url.port) {|http|
    http.get("/base/feeds/snippets/?bq=[upc(text):\"#{upc}\"]&max-results=1&start-index=1&orderby=relevancy")
  }
  xml = REXML::Document.new(res.body)
  # If xml search returned a result..
  if xml.elements["//feed/openSearch:totalResults"].text.to_i > 0
    entry = xml.elements["//feed/entry"]
    return {:title   => entry.elements["title"].text,
            :image   => entry.elements["g:image_link"].text}
  else
    return false
  end
end

module GroceryGadgetClient
  module Frames
    def view_main
      lcd_puts "Scan Product Barcode", 1, 20
      lcd_puts "or Type Product Name", 21, 40
    end
  end
end

include GroceryGadgetClient::Frames

# Main Loop (Drops any errors and restarts.)
# ------------------------------------------------------------
while true
  begin
    # Load $config.
    $config = YAML.load_file(relative("config/config.yml"))
    $barcode_cache = YAML.load_file(relative("config/saved_barcodes.yml")) || {} rescue {}

    # Loop until LCD is connected
    l_connect = false
    while not l_connect
      begin
        $dsp420 = DSP420.new $config["lcd_devnode"]
        l_connect = true
      rescue
        puts "No LCD connected."
        sleep 2
      end
    end

    while true
      # Show main instructions.
      view_main

      # Wait for keypress.
      key = getch

      barcode = nil
      if key <= 128 && key >= 32
        if key.chr.match /\d/
          # -- Starts with digit, is a barcode.
          lcd_puts "[Barcode]".center(20), 1, 20
          lcd_puts ":: ", 21, 40
          # Retrieve rest of digits and then newline key.
          barcode = ""
          begin
            barcode += key.chr
            lcd_puts barcode.ljust(20)[0,16], 24, 40
          end until (key = getch) == 10

          # Search for barcode in Google Base if barcode is not in local cache.
          unless product = $barcode_cache[barcode]
            lcd_puts "Searching...".center(20), 1, 40

            if product = google_base_upc(barcode)
              # Ask the user if the product title is correct
              lcd_puts "Is this ok? (Y/N)", 1, 20

              # Scroll title in thread, kill thread on keypress.
              scroll_thread = Thread.new do
                title_widget = Widget.new(product[:title], [2,1], 20)
                while true
                  title_widget.increment_scroll
                  lcd_puts title_widget.render, 21, 40
                  sleep 0.3
                end
              end

              key = getch
              scroll_thread.kill

              unless key == ?Y || key == ?y
                # Prompt for title if not correct.
                product[:title] = $dsp420.lcd_prompt("Item name:")
              end
            else
              # If google base comes back empty handed, prompt user for title..
              product = {:title => $dsp420.lcd_prompt("Please enter item:")}
            end
          end
        else
          # -- Else, user is beginning to type a product.
          product = {:title => $dsp420.lcd_prompt("Item name:", key.chr, 1)}
        end

        # If product title is blank, do nothing and restart loop.
        if product[:title] && product[:title] != ""
          # Store product => barcode in local cache if barcode was scanned and has changed.
          if barcode && $barcode_cache[barcode] != product
            $barcode_cache[barcode] = product
            save_barcode_cache
          end

          # Add item to grocery gadgets list.
          lcd_puts "Adding to list...".center(20), 1, 20
          lcd_puts product[:title][0,20].center(20), 21, 40
          sleep 2
        end
      end
    end

  rescue
  end
end

