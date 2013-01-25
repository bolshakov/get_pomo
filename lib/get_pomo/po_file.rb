require 'get_pomo/translation'

module GetPomo
  class PoFile
    def self.parse(text)
      PoFile.new.add_translations_from_text(text)
    end

    def self.to_text(translations)
      p = PoFile.new(:translations=>translations)
      p.to_text
    end

    attr_reader :translations

    def initialize(options = {})
      @translations = options[:translations] || []
    end

    #the text is split into lines and then converted into logical translations
    #each translation consists of comments(that come before a translation)
    #and a msgid / msgstr
    def add_translations_from_text(text)
      start_new_translation
      text.split(/$/).each_with_index do |line,index|
        @line_number = index + 1
        next if line.empty?
        if method_call? line
          parse_method_call line
        elsif comment? line
          add_comment line
        else
          add_string line
        end
      end
      start_new_translation #instance_variable has to be overwritten or errors can occur on next add
      translations
    end

    def to_text
      GetPomo.unique_translations(translations).map {|translation|
        comment = translation.comment.to_s.split(/\n|\r\n/).map{|line|"##{line}\n"}*''
        msgid_and_msgstr = if translation.plural?
          msgids =
          %Q(msgid #{format_text(translation.msgid[0])}\n)+
          %Q(msgid_plural #{format_text(translation.msgid[1])}\n)

          msgstrs = []
          translation.msgstr.each_with_index do |msgstr,index|
            msgstrs << %Q(msgstr[#{index}] #{format_text(msgstr)})
          end

          msgids + (msgstrs*"\n")
        else
          %Q(msgid #{format_text(translation.msgid)}\n)+
          %Q(msgstr #{format_text(translation.msgstr)})
        end

        comment + msgid_and_msgstr
      } * "\n\n"
    end

    private

    def format_text(text)
      lines = text.lines
      if lines.count == 1
        "\"#{lines.first}\""
      else
        lines.inject('""') { |string, line|
          #pp "\"#{line.rstrip}\\n\"\n"
          string += "\n\"#{line.rstrip}\\n\""
        }.strip
      end
    end

    #e.g. # fuzzy
    def comment?(line)
      line =~ /^\s*#/
    end

    def add_comment(line)
      start_new_translation if translation_complete?
      @current_translation.add_text(line.strip.sub('#','')+"\n",:to=>:comment)
    end

    #msgid "hello"
    def method_call?(line)
      line =~ /^\s*[a-z]/
    end

    #msgid "hello" -> method call msgid + add string "hello"
    def parse_method_call(line)
      method, string = line.match(/^\s*([a-z0-9_\[\]]+)(.*)/)[1..2]
      raise "no method found" unless method

      start_new_translation if method == 'msgid' and translation_complete?
      @last_method = method.to_sym
      add_string(string)
    end

    #"hello" -> hello
    def add_string(string)
      return if string.strip.empty?

      # A string passed directly to method. E.g.
      #  msgid "the string"
      #  'string' equals "the string"
      #
      if  string.strip =~ /^['"](.*)['"]$/
        string =$1

      # A string passed as mutiline string. E.g.
      #  msgid ""
      #  "the string\n"
      #  "the end\n"
      #  'string' equals "\n\"the string\n\""
      #
      elsif string.lines.count == 2 && string.lines.to_a.last.strip  =~ /^['"](.*)['"]$/
        string =$1
      else
        raise "not string format: #{string.inspect} on line #{@line_number}"
      end

      @current_translation.add_text(string.strip.gsub("\\n", "\n"), :to=>@last_method)
    end

    def translation_complete?
      return false unless @current_translation
      @current_translation.complete?
    end
  
    def store_translation
      if @current_translation.complete?
        # remove trailing newlines
        [:msgstr, :msgid].each do |method|
          value = @current_translation.send(method)

          value = if value.kind_of? Array
            value.map &:strip
          else
            value.strip
          end
          @current_translation.send("#{method}=", value)
        end

        @translations.push @current_translation
      end
    end

    def start_new_translation
      store_translation if translation_complete?
      @current_translation = Translation.new
    end
  end
end
