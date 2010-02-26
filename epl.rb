class Epl
  # ruby magic
  require 'open3'
  attr_accessor :width # page width in inches
  attr_accessor :height # page height in inches
  attr_accessor :dpi 
  attr_accessor :font # current font size, 1..5
  attr_accessor :barcode_pattern #see BARCODE_PATTEN
  attr_accessor :barcode_narrow_width # width in dots of narrow bars
  attr_accessor :barcode_wide_width # width in dots of wide bars
  attr_accessor :barcode_height # height in dots of barcode
  attr_accessor :barcode_textify # show barcode data on barcode?
  attr_accessor :line_width
  attr_accessor :rotation # current rotation, 0..3 or :portrait or :landscape
  attr_accessor :margin_x
  attr_accessor :margin_y
  attr_accessor :current_x
  attr_accessor :current_y
  attr_accessor :cmd_stack

  # initialization
  BARCODE_PATTERN = { :code39                          => '3'  ,
                      :code39_checksum                 => '3C' ,
                      :code93                          => '9'  ,
                      :code128_ucc                     => '0'  ,
                      :code128_auto                    => '1'  ,
                      :code_128_mode_a                 => '1A' ,
                      :code_128_mode_b                 => '1B' ,
                      :code_128_mode_c                 => '1C' ,
                      :codabar                         => 'K'  ,
                      :ean8                            => 'E80',
                      :ean8_plus2                      => 'E82',
                      :ean8_plus5                      => 'E85',
                      :ean13                           => 'E30',
                      :ean13_plus2                     => 'E32',
                      :ean13_plus5                     => 'E35',
                      :german_post_code                => '2G' ,
                      :interleaved_2of5                => '2'  ,
                      :interleaved_2of5_checksum_mod10 => '2C' ,
                      :postnet                         => 'P'  ,
                      :planet                          => 'PL' ,
                      :japanese_postnet                => 'J'  ,
                      :ucc_ean128                      => '1E',
                      :upc_a                           => 'UA0',
                      :upc_a_plus2                     => 'UA2',
                      :upc_a_plus5                     => 'UA5',
                      :upc_e                           => 'UE0',
                      :upc_e_plus2                     => 'UE2',
                      :upc_e_plus5                     => 'UE5',
                      :upc_interleaved_2of5            => '2U' ,
                      :plessey_checksum_mod10          => 'L'  ,
                      :msi1_checksum_mod10             => 'L'  ,
                      :msi3_checksum_mod10             => 'M'   }
                       
  ROTATION = { 'portrait'  => 0,
               'landscape' => 1 }
               
  CHAR_SIZE_203 =  { 5 => {:width => 32, :height => 48 },
                     4 => {:width => 14, :height => 24 },
                     3 => {:width => 12, :height => 20 },
                     2 => {:width => 10, :height => 16 },
                     1 => {:width => 8, :height => 12 } }
  CHAR_SPACE_203 = { 5 => {:width => 2, :height => 1 }, 
                     4 => {:width => 1, :height => 1 },
                     3 => {:width => 1, :height => 1 },
                     2 => {:width => 1, :height => 1 },
                     1 => {:width => 1, :height => 1 } }
                     
  def initialize(attrs = {})
    @width = (attrs[:width] || 4).to_f
    @height = (attrs[:height] || 4).to_f
    @dpi = (attrs[:dpi] || 203).to_f
    @font = (attrs[:font] || 4).to_i
    @barcode_pattern = (BARCODE_PATTERN[attrs[:barcode_patten]] || attrs[:barcode_patten] || '3')
    @barcode_narrow_width = (attrs[:barcode_narrow_width] || 3).to_i
    @barcode_wide_width = (attrs[:barcode_wide_width] || @barcode_narrow_width * 3).to_i
    @barcode_height = (attrs[:barcode_height] || (@dpi/2).round).to_i
    @barcode_textify = (attrs[:barcode_textify] || false)
    @line_width = (attrs[:line_width] || 3).to_i
    @rotation = (attrs[:rotation] || :portrait)
    @margin_x = (attrs[:margin_x] || 10).to_i
    @margin_y = (attrs[:margin_y] || 10).to_i
    @current_x = @margin_x
    @current_y = @margin_y
    @cmd_stack = []
  end
  
  # helpers 
  def string_width(str, width_factor = 1, font = @font)
    ((((eval("CHAR_SIZE_#{@dpi.to_i}[#{font}][:width]") + (eval("CHAR_SPACE_#{@dpi.to_i}[#{font}][:width]") * 2))*str.to_s.strip.size) - eval("CHAR_SPACE_#{@dpi.to_i}[#{font}][:width]")) * width_factor)
  end
  def string_height(str, height_factor =1, font = @font)
    ((eval("CHAR_SIZE_#{@dpi.to_i}[#{font}][:height]") + eval("CHAR_SPACE_#{@dpi.to_i}[#{font}][:height]")) * height_factor)
  end
  
  def barcode_width(str, pattern = @barcode_pattern, narrow_width = @barcode_narrow_width, wide_width = @barcode_wide_width)
    case pattern
      when '3', '3C'
        ((narrow_width * 6) + (wide_width * 3)) * (str.length + 2)
    end
  end
  
  def rotated_x
    case rotate(@rotation)
    when 0 # 0°
      (@current_x).to_i
    when 1 # 90°
      ((@height * @dpi) - @current_y).to_i
    end
  end
  def rotated_y
    case rotate(@rotation)
    when 0 # 0°
      (@current_y).to_i
    when 1 # 90°
      (@current_x).to_i
    end
  end
  
  def rotate(val)
    if ROTATION[val.to_s]
      ROTATION[val.to_s]
    elsif (0..3).to_a.include?(val.to_i)
      val.to_i
    elsif val.to_i % 90 == 0
      (val.to_i / 90) % 4
    else
      0
    end
  end
  
  def escape(str)
    str.to_s.strip.gsub("\"","\\\"").gsub("\\","\\\\")
  end

  # business logic
  def manual_code(str)
    @cmd_stack << str
  end
  
  def clear_stack
    @cmd_stack = []
  end
  
  def move_to_origin
    @current_x = @margin_x
    @current_y = @margin_y
  end
  
  def move_to(x,y)
    @current_x = x.to_i
    @current_y = y.to_i
  end
  
  def move_right(val)
    @current_x += val.to_i
  end
  def move_left(val)
    @current_x -= val.to_i
  end
  def move_down(val)
    @current_y += val.to_i
  end
  def move_up(val)
    @current_y -= val.to_i
  end
  
  alias_method :super_print, :print
  def print(str, align = :leave, reverse = false, width_factor = 1, height_factor = 1, font = @font, rotation = @rotation)
    @rotation = rotate(rotation)
    case align.to_s
    when 'left'
      @current_x = @margin_x
    when 'right'
      @current_x = ((@width * @dpi) - @margin_x - string_width(str, width_factor, font)).round.to_i
    when 'center'
      @current_x = (((@width * @dpi) - string_width(str, width_factor, font)) / 2).round.to_i
    end
    str = str.to_s.upcase if font == 5
    @cmd_stack << "A#{rotated_x},#{rotated_y},#{@rotation},#{font},#{width_factor},#{height_factor},#{reverse ? 'R' : 'N'},\"#{escape(str)}\""
    @current_x += string_width(str, width_factor, font)
    return self
  end

  def print_at(x, y, str, align = :leave, reverse = false, width_factor = 1, height_factor = 1, font = @font, rotation = @rotation)
    @current_x = x
    @current_y = y
    print(str, align, reverse, width_factor, height_factor, font, rotation)
  end
  
  alias_method :super_puts, :puts
  def puts(str, align = :left, reverse = false, width_factor = 1, height_factor = 1, font = @font, rotation = @rotation)
    print(str, align, reverse, width_factor, height_factor, font, rotation)
    @current_x = @margin_x
    @current_y += string_height(str, height_factor, font)
    return self
  end
  
  def barcode(str, rotation = @rotation, pattern = @barcode_pattern, narrow_width = @barcode_narrow_width, wide_width = @barcode_wide_width, height = @barcode_height, human_readable = @barcode_textify)
    @rotation = rotate(rotation)
    @cmd_stack << "B#{rotated_x},#{rotated_y},#{@rotation},#{pattern},#{narrow_width},#{wide_width},#{height},#{human_readable ? 'B' : 'N'},\"#{escape(str)}\""
    return self
  end
  
  def print_barcode(str, align = :leave, rotation = @rotation, pattern = @barcode_pattern, narrow_width = @barcode_narrow_width, wide_width = @barcode_wide_width, height = @barcode_height, human_readable = @barcode_textify)
    @rotation = rotate(rotation)
    @barcode_pattern ||= pattern
    @barcode_narrow_width ||= narrow_width.to_i
    @barcode_wide_width ||= wide_width.to_i
    @barcode_height ||= height.to_i
    @barcode_textify ||= human_readable
    case align.to_s
    when 'left'
      @current_x = @margin_x
    when 'right'
      @current_x = ((@width * @dpi) - @margin_x - barcode_width(str)).round.to_i
    when 'center'
      @current_x = (((@width * @dpi) - barcode_width(str)) / 2).round.to_i
    end
    barcode(str)
  end
  
  def puts_barcode(str, align = :left, rotation = @rotation, pattern = @barcode_pattern, narrow_width = @barcode_narrow_width, wide_width = @barcode_wide_width, height = @barcode_height, human_readable = @barcode_textify)
    print_barcode(str, align, rotation, pattern, narrow_width, wide_width, height, human_readable)
    @current_x = @margin_x
    @current_y += height
    return self
  end
  
  def barcode_at(x, y, str, rotation = @rotation, pattern = @barcode_pattern, narrow_width = @barcode_narrow_width, wide_width = @barcode_wide_width, height = @barcode_height, human_readable = @barcode_textify)
    @current_x = x
    @current_y = y
    barcode(str, rotation, pattern, narrow_width, wide_width, height, human_readable)
  end
  
  def line(start_x, start_y, end_x, end_y, width = @line_width)
    @cmd_stack << "LS#{start_x.to_i},#{start_y.to_i},#{width.to_i},#{end_x.to_i},#{end_y.to_i}"
    return self
  end
  
  def export(qty = 1)
    "\nN\n#{@cmd_stack.join("\n")}\n\P#{qty}\n"
  end
  
  def printout(printer = 'tagprinter', qty = 1)
    Open3.popen3("lpr -P #{printer} -o raw") do |stdin, stdout, stderr|
      stdin.puts export(qty)
    end
  end
  
end
