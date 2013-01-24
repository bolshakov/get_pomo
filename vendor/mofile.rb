=begin
    mofile.rb - A simple class for operating GNU MO file.

    Copyright (C) 2003-2008  Masao Mutoh
    Copyright (C) 2002  Masahiro Sakai, Masao Mutoh
    Copyright (C) 2001  Masahiro Sakai

        Masahiro Sakai                  <s01397ms at sfc.keio.ac.jp>
        Masao Mutoh                     <mutoh at highway.ne.jp>

    You can redistribute this file and/or modify it under the same term
    of Ruby.  License of Ruby is included with Ruby distribution in
    the file "README".

    $Id: mo.rb,v 1.10 2008/06/17 16:40:52 mutoh Exp $
=end

require 'stringio'

module GetPomo
  module GetText
    class MOFile < Hash
      class InvalidFormat < RuntimeError; end;

      attr_reader :filename

      Header = Struct.new(:magic,
                          :revision,
                          :nstrings,
                          :orig_table_offset,
                          :translated_table_offset,
                          :hash_table_size,
                          :hash_table_offset)

      # The following are only used in .mo files
      # with minor revision >= 1.
      class HeaderRev1 < Header
        attr_accessor :n_sysdep_segments,
        :sysdep_segments_offset,
        :n_sysdep_strings,
        :orig_sysdep_tab_offset,
        :trans_sysdep_tab_offset
      end

      MAGIC_BIG_ENDIAN    = "\x95\x04\x12\xde"
      MAGIC_LITTLE_ENDIAN = "\xde\x12\x04\x95"

      def self.open(arg = nil, output_charset = nil)
        result = self.new(output_charset)
        result.load(arg)
      end

      def initialize(output_charset = nil)
        @filename = nil
        @last_modified = nil
        @little_endian = true
        @output_charset = output_charset
        super()
      end

      def update!
        if FileTest.exist?(@filename)
          st = File.stat(@filename)
          load(@filename) unless (@last_modified == [st.ctime, st.mtime])
        else
          warn "#{@filename} was lost." if $DEBUG
          clear
        end
        self
      end

      def load(arg)
        if arg.kind_of? String
          begin
            st = File.stat(arg)
            @last_modified = [st.ctime, st.mtime]
          rescue Exception
          end
          load_from_file(arg)
        else
          load_from_stream(arg)
        end
        @filename = arg
        self
      end

      def load_from_stream(io)
        magic = io.read(4)
        case magic
        when MAGIC_BIG_ENDIAN
          @little_endian = false
        when MAGIC_LITTLE_ENDIAN
          @little_endian = true
        else
          raise InvalidFormat.new(sprintf("Unknown signature %s", magic.dump))
        end

        endian_type6 = @little_endian ? 'V6' : 'N6'
        endian_type_astr = @little_endian ? 'V*' : 'N*'

        header = HeaderRev1.new(magic, *(io.read(4 * 6).unpack(endian_type6)))

        if header.revision == 1
          # FIXME: It doesn't support sysdep correctly.
          header.n_sysdep_segments = io.read(4).unpack(endian_type6)
          header.sysdep_segments_offset = io.read(4).unpack(endian_type6)
          header.n_sysdep_strings = io.read(4).unpack(endian_type6)
          header.orig_sysdep_tab_offset = io.read(4).unpack(endian_type6)
          header.trans_sysdep_tab_offset = io.read(4).unpack(endian_type6)
        elsif header.revision > 1
          raise InvalidFormat.new(sprintf("file format revision %d isn't supported", header.revision))
        end
        io.pos = header.orig_table_offset
        orig_table_data = io.read((4 * 2) * header.nstrings).unpack(endian_type_astr)

        io.pos = header.translated_table_offset
        trans_table_data = io.read((4 * 2) * header.nstrings).unpack(endian_type_astr)

        original_strings = Array.new(header.nstrings)
        for i in 0...header.nstrings
          io.pos = orig_table_data[i * 2 + 1]
          original_strings[i] = io.read(orig_table_data[i * 2 + 0])
        end

        clear
        for i in 0...header.nstrings
          io.pos = trans_table_data[i * 2 + 1]
          str = io.read(trans_table_data[i * 2 + 0]).force_encoding('utf-8')

          if (! original_strings[i]) || original_strings[i] == ""
            if str
              @charset = nil
              @nplurals = nil
              @plural = nil
              str.each_line{|line|
                if /^Content-Type:/i =~ line and /charset=((?:\w|-)+)/i =~ line
                  @charset = $1
                elsif /^Plural-Forms:\s*nplurals\s*\=\s*(\d*);\s*plural\s*\=\s*([^;]*)\n?/ =~ line
                  @nplurals = $1
                  @plural = $2
                end
                break if @charset and @nplurals
              }
              @nplurals = "1" unless @nplurals
              @plural = "0" unless @plural
            end
          else
            if @output_charset && @charset
              str = str.encode(@output_charset, @charset)
            end
          end
          self[original_strings[i]] = str.freeze
        end
        self
      end

      # Is this number a prime number ?
      # http://apidock.com/ruby/Prime
      def prime?(number)
        ('1' * number) !~ /^1?$|^(11+?)\1+$/
      end

      def next_prime(seed)
        require 'mathn'
        prime = Prime.new
        while current = prime.succ
          return current if current > seed
        end
      end

      # From gettext-0.12.1/gettext-runtime/intl/hash-string.h
      # Defines the so called `hashpjw' function by P.J. Weinberger
      # [see Aho/Sethi/Ullman, COMPILERS: Principles, Techniques and Tools,
      # 1986, 1987 Bell Telephone Laboratories, Inc.]
      HASHWORDBITS = 32
      def hash_string(str)
        hval = 0
        i = 0
        str.each_byte do |b|
          break if b == '\0'
          hval <<= 4
          hval += b.to_i
          g = hval & (0xf << (HASHWORDBITS - 4))
          if (g != 0)
            hval ^= g >> (HASHWORDBITS - 8)
            hval ^= g
          end
        end
        hval
      end

      def load_from_file(filename)
        @filename = filename
        begin
          File.open(filename, 'rb:utf-8'){|f| load_from_stream(f)}
        rescue => e
          e.set_backtrace("File: #{@filename}")
          raise e
        end
      end

      def save_to_file(filename)
        File.open(filename, 'wb'){|f| save_to_stream(f)}
      end

      def set_comment(msgid_or_sym, comment)
        #Do nothing
      end


      attr_accessor :little_endian, :path, :last_modified
      attr_reader :charset, :nplurals, :plural
    end
  end
end
