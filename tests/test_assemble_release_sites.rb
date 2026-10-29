# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "stringio"
require "tmpdir"
require_relative "../scripts/assemble_release_sites"

class AssembleReleaseSitesTest < Minitest::Test
  def setup
    @temporary = Pathname.new(Dir.mktmpdir("manual-release-sites-"))
    @site = @temporary / "_site"
    @releases = @temporary / "_releases"
    @warnings = StringIO.new
    write(@site / "index.html", "development")
  end

  def teardown
    FileUtils.remove_entry(@temporary)
  end

  def write(path, content)
    path.dirname.mkpath
    File.write(path, content)
  end

  def release(tag, marker = tag)
    build = @temporary / "build-#{tag}"
    write(build / "index.html", marker)
    write(build / "user-guide" / "beam.html", marker)
    archive = @releases / tag / ReleaseSites::ARCHIVE
    archive.dirname.mkpath
    _, error, status = Open3.capture3("tar", "-czf", archive.to_s, "-C", build.to_s, ".")
    assert status.success?, error
  end

  def manifest(directory)
    JSON.parse(File.read(directory / "versions.json"))
  end

  def test_keeps_highest_patch_per_series_newest_first
    tags = %w[OPALX-1.0.0 OPALX-1.0.2 OPALX-1.1.0 OPALX-1.0.10 OPAL-2024.1.0]
    assert_equal [%w[1.1 OPALX-1.1.0], %w[1.0 OPALX-1.0.10]],
                 ReleaseSites.series(tags).map { |entry| entry.values_at("id", "tag") }
  end

  def test_without_releases_writes_development_only_manifest
    ReleaseSites.assemble(@site, @releases, warnings: @warnings)
    assert_equal({ "current" => "dev", "latest" => nil, "versions" => [ReleaseSites::DEVELOPMENT] },
                 manifest(@site))
  end

  def test_unpacks_releases_and_writes_one_manifest_per_directory
    release("OPALX-1.0.0", "old patch")
    release("OPALX-1.0.1")
    release("OPALX-1.1.0")
    ReleaseSites.assemble(@site, @releases, warnings: @warnings)

    assert_equal "development", File.read(@site / "index.html")
    assert_equal "OPALX-1.0.1", File.read(@site / "1.0" / "user-guide" / "beam.html")
    assert_equal "OPALX-1.1.0", File.read(@site / "1.1" / "index.html")

    root = manifest(@site)
    assert_equal "dev", root["current"]
    assert_equal "1.1", root["latest"]
    assert_equal ["", "1.1/", "1.0/"], root["versions"].map { |version| version["path"] }
    assert_equal "OPALX 1.0.1", root["versions"].last["label"]
    assert_equal root.merge("current" => "1.0"), manifest(@site / "1.0")
    assert_equal root.merge("current" => "1.1"), manifest(@site / "1.1")
  end

  def test_warns_about_unusable_release_directories
    (@releases / "nightly").mkpath
    (@releases / "OPALX-2.0.0").mkpath
    ReleaseSites.assemble(@site, @releases, warnings: @warnings)
    assert_match(/ignoring nightly/, @warnings.string)
    assert_match(/OPALX-2\.0\.0 has no #{Regexp.escape(ReleaseSites::ARCHIVE)}/, @warnings.string)
    assert_equal ["dev"], manifest(@site)["versions"].map { |version| version["id"] }
  end

  def test_refuses_to_merge_into_an_existing_directory
    write(@site / "1.0" / "index.html", "chapter")
    release("OPALX-1.0.0")
    error = assert_raises(RuntimeError) { ReleaseSites.assemble(@site, @releases, warnings: @warnings) }
    assert_match(/would overwrite/, error.message)
  end
end
