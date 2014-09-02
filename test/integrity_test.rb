# encoding: utf-8
require 'test_helper'
require 'json'
require 'digest/md5'

class IntegrityTest < TestCase
  test "images on disk correlate 1-1 with emojis" do
    images_on_disk = Dir["#{Emoji.images_path}/**/*.png"].map do |f|
      f.sub(Emoji.images_path, '') unless File.symlink? f
    end.compact
    expected_images = Emoji.all.map { |emoji| '/emoji/%s' % emoji.image_filename }

    missing_images = expected_images - images_on_disk
    assert_equal 0, missing_images.size, "these images are missing on disk:\n  #{missing_images.join("\n  ")}\n"

    extra_images = images_on_disk - expected_images
    # Yeah there are extra symlinks now.
    #assert_equal 0, extra_images.size, "these images don't match any emojis:\n  #{extra_images.join("\n  ")}\n"
  end

  test "images on disk have no duplicates" do
    hashes = Hash.new { |h,k| h[k] = [] }
    Dir["#{Emoji.images_path}/**/*.png"].each do |image_file|
      unless File.symlink? image_file
        checksum = Digest::MD5.file(image_file).to_s
        hashes[checksum] << image_file
      end
    end

    hashes.each do |checksum, filenames|
      assert_equal 1, filenames.length,
        "These images share the same checksum: " +
        filenames.map {|f| f.sub(Emoji.images_path, '') }.join(', ')
    end
  end

  test "images on disk are 64x64" do
    mismatches = []
    Dir["#{Emoji.images_path}/**/*.png"].each do |image_file|
      width, height = png_dimensions(image_file)
      unless width == 64 && height == 64
        mismatches << "%s: %dx%d" % [
          image_file.sub(Emoji.images_path, ''),
          width,
          height
        ]
      end
    end
    assert_equal ["/emoji/shipit.png: 75x75"], mismatches
  end

  test "missing or incorrect unicodes" do
    missing = source_unicode_emoji - Emoji.all.flat_map(&:unicode_aliases)
    assert_equal 0, missing.size, missing_unicodes_message(missing)
  end

  private
    def missing_unicodes_message(missing)
      "Missing or incorrect unicodes:\n".tap do |message|
        missing.each do |raw|
          emoji = Emoji::Character.new(nil)
          emoji.add_unicode_alias(raw)
          message << "#{emoji.raw}  (#{emoji.hex_inspect})"
          codepoint = emoji.raw.codepoints[0]
          if candidate = Emoji.all.detect { |e| !e.custom? && e.raw.codepoints[0] == codepoint }
            message << " - might be #{candidate.raw}  (#{candidate.hex_inspect}) named #{candidate.name}"
          end
          message << "\n"
        end
      end
    end

    def db
      @db ||= JSON.parse(File.read(File.expand_path("../../db/Category-Emoji.json", __FILE__)))
    end

    def source_unicode_emoji
      @source_unicode_emoji ||= begin
        # Chars from OS X palette which must have VARIATION SELECTOR-16 to render:
        specials = ["🈷", "🈂", "🅰", "🅱", "🅾", "©", "®", "™", "〰"]
        db["EmojiDataArray"]
          .flat_map { |data| data["CVCategoryData"]["Data"].split(",") }
          .map { |raw| specials.include?(raw) ? "#{raw}\u{fe0f}" : raw }
      end
    end

    def png_dimensions(file)
      png = File.open(file, "rb") { |f| f.read(1024) }
      png.unpack("x16N2")
    end
end
