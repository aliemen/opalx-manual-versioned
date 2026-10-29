#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "pathname"

# Places frozen release manuals beside the development build before the Pages
# upload and writes the versions.json files read by
# assets/scripts/release-selector.html.
#
# The development build stays at the site root. Each OPALX-<major>.<minor>.<patch>
# release archive is unpacked into <major>.<minor>/, so a patch release replaces
# its series. Every manual directory receives its own versions.json whose
# "current" entry tells the page where it sits below the site root.
module ReleaseSites
  ARCHIVE = "opalx-manual-site.tar.gz"
  TAG = /\AOPALX-(\d+)\.(\d+)\.(\d+)\z/
  DEVELOPMENT = { "id" => "dev", "label" => "Development (main)", "path" => "" }.freeze

  module_function

  # Returns the highest patch release of each series, newest series first.
  def series(tags)
    tags.filter_map { |tag| (match = TAG.match(tag)) && [tag, match.captures.map(&:to_i)] }
        .group_by { |_, (major, minor, _)| [major, minor] }
        .map { |_, releases| releases.max_by { |_, version| version } }
        .sort_by { |_, version| version }
        .reverse
        .map do |tag, (major, minor, patch)|
          {
            "id" => "#{major}.#{minor}",
            "label" => "OPALX #{major}.#{minor}.#{patch}",
            "path" => "#{major}.#{minor}/",
            "tag" => tag
          }
        end
  end

  # Expects releases_dir/<tag>/opalx-manual-site.tar.gz as downloaded from the
  # GitHub releases; directories without an archive or with other tag names are
  # ignored.
  def assemble(site, releases_dir, warnings: $stderr)
    site = Pathname.new(site)
    releases_dir = Pathname.new(releases_dir)
    raise ArgumentError, "development build is missing: #{site}" unless (site / "index.html").file?

    tags = releases_dir.directory? ? releases_dir.children.select(&:directory?).map { |dir| dir.basename.to_s } : []
    tags.each do |tag|
      warnings.puts "warning: release sites: ignoring #{tag}, not OPALX-<major>.<minor>.<patch>" unless TAG.match?(tag)
      warnings.puts "warning: release sites: #{tag} has no #{ARCHIVE}" unless (releases_dir / tag / ARCHIVE).file?
    end

    releases = series(tags.select { |tag| (releases_dir / tag / ARCHIVE).file? })
    releases.each do |release|
      target = site / release["path"]
      # A chapter directory of that name would be silently mixed with the release.
      raise "release #{release['tag']} would overwrite #{target}" if target.exist?

      target.mkpath
      extract(releases_dir / release["tag"] / ARCHIVE, target)
      raise "release #{release['tag']} has no index.html at its archive root" unless (target / "index.html").file?
    end

    versions = [DEVELOPMENT, *releases]
    latest = releases.first&.fetch("id")
    write_manifest(site, DEVELOPMENT["id"], latest, versions)
    releases.each { |release| write_manifest(site / release["path"], release["id"], latest, versions) }
    versions
  end

  def extract(archive, target)
    _, error, status = Open3.capture3("tar", "-xzf", archive.to_s, "-C", target.to_s)
    raise "cannot unpack #{archive}: #{error}" unless status.success?
  end

  def write_manifest(directory, current, latest, versions)
    manifest = { "current" => current, "latest" => latest, "versions" => versions }
    File.write(directory / "versions.json", "#{JSON.pretty_generate(manifest)}\n")
  end
end

if $PROGRAM_NAME == __FILE__
  abort "usage: #{File.basename($PROGRAM_NAME)} SITE_DIR RELEASES_DIR" unless ARGV.length == 2

  ReleaseSites.assemble(*ARGV).each do |version|
    puts "#{version['label']}: /#{version['path']}"
  end
end
