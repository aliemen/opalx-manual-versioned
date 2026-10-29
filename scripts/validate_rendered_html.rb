#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "pathname"
require "uri"
require "yaml"

ROOT = Pathname.new(__dir__).parent.expand_path
SITE = ROOT / "_site"
PROFILE = ENV.fetch("QUARTO_PROFILE", "opalx")
PROFILE_FILE = ROOT / "_quarto-#{PROFILE}.yml"

abort "error: rendered site is missing: #{SITE}" unless SITE.directory?
abort "error: unknown Quarto profile: #{PROFILE}" unless PROFILE_FILE.file?

profile = YAML.safe_load(File.read(PROFILE_FILE), permitted_classes: [], aliases: false)
expected_documents = profile.fetch("documents-base-url")
expected_repository = profile.fetch("manual-repository-url")
html_files = SITE.glob("**/*.html")
combined_html = html_files.map { |path| File.read(path) }.join("\n")

errors = []
errors << "render does not contain the profile's document base URL" unless combined_html.include?(expected_documents)
errors << "render does not contain the profile's manual repository URL" unless combined_html.include?(expected_repository)
errors << "render does not contain Quarto's color-scheme persistence" unless combined_html.include?("quarto-color-scheme")
errors << "render does not contain OPALX sidebar-state persistence" unless combined_html.include?("opalx-sidebar-state-v1")
errors << "sidebar persistence does not wait for Quarto initialization" unless combined_html.include?("opalxSidebarStateReady")
errors << "render does not contain documentation-version persistence" unless combined_html.include?("opalx-documentation-version-v1")
errors << "render does not contain the accessible documentation-version selector" unless combined_html.include?("Select documentation version")
errors << "render does not contain direct-anchor version handling" unless combined_html.include?("revealHashTarget")
errors << "render does not contain the manual release selector" unless combined_html.include?("opalx-release-select")
errors << "render does not contain the distribution sidebar manifest" unless combined_html.include?("page-toc:beam-distributions")
errors << "render still contains the removed Structures sidebar manifest" if combined_html.include?("page-toc:structures")
errors << "render does not contain the field-solver sidebar manifest" unless combined_html.include?("page-toc:field-solver")
errors << "render does not contain the elements sidebar manifest" unless combined_html.include?("page-toc:elements")
errors << "render does not contain the regression-test source URL" unless combined_html.include?("https://github.com/OPALX-project/regression-tests-x/blob/master")

distribution_html_path = SITE / "user-guide/beam-distributions.html"
if distribution_html_path.file?
  distribution_html = File.read(distribution_html_path)
  distribution_anchors = %w[
    emissionsource emissionsourcelist distribution uniform gauss multivariategauss flattop
    opalflattop fromfile emittedfromfile reproducibility-limitations
  ]
  distribution_anchors.each do |anchor|
    errors << "beam-distributions render is missing ##{anchor}" unless distribution_html.match?(/\bid=["']#{Regexp.escape(anchor)}["']/)
  end
  {
    "emissionsource" => /data-number=["']\d+\.1["']/,
    "emissionsourcelist" => /data-number=["']\d+\.2["']/,
    "distribution" => /data-number=["']\d+\.3["']/,
    "uniform" => /data-number=["']\d+\.3\.1["']/,
    "gauss" => /data-number=["']\d+\.3\.2["']/,
    "emittedfromfile" => /data-number=["']\d+\.3\.7["']/
  }.each do |anchor, numbering|
    section = distribution_html[/<section\s+id=["']#{Regexp.escape(anchor)}["'][\s\S]*?<\/section>/]
    errors << "beam-distributions ##{anchor} has incorrect automatic numbering" unless section&.match?(numbering)
  end
  errors << "beam-distributions does not suppress its duplicate margin TOC" unless distribution_html.include?("opalx-sidebar-page-toc")
  errors << "distribution sidebar lacks an accessible chapter toggle" unless distribution_html.include?("Toggle Beam and Distributions sections")
  errors << "distribution sidebar lacks an accessible type toggle" unless distribution_html.include?("Toggle DISTRIBUTION types")
  errors << "distribution sidebar state keys are not rendered" unless distribution_html.include?("dataset.opalxStateKey")
else
  errors << "render is missing user-guide/beam-distributions.html"
end

field_solver_html_path = SITE / "user-guide/field-solver/index.html"
if field_solver_html_path.file?
  field_solver_html = File.read(field_solver_html_path)
  field_solver_anchors = %w[
    solver-backends solver-none solver-fft solver-open solver-p3m solver-cg solver-2d5 fieldsolver-parameters
    mesh-pic-cycle boundary-conditions open-periodic-boundaries generic-dirichlet-boundaries
    space-charge-modes monolithic-mode binned-mode explicit-image-charges
    shifted-greens-correction compatibility-selection accuracy-cost binning
  ]
  field_solver_anchors.each do |anchor|
    errors << "field-solver render is missing ##{anchor}" unless field_solver_html.match?(/\bid=["']#{Regexp.escape(anchor)}["']/)
  end
  {
    "solver-backends" => /data-number=["']\d+\.1["']/,
    "solver-none" => /data-number=["']\d+\.1\.1["']/,
    "solver-p3m" => /data-number=["']\d+\.1\.4["']/,
    "solver-cg" => /data-number=["']\d+\.1\.5["']/,
    "fieldsolver-parameters" => /data-number=["']\d+\.2["']/,
    "generic-dirichlet-boundaries" => /data-number=["']\d+\.4\.2["']/,
    "shifted-greens-correction" => /data-number=["']\d+\.5\.4["']/,
    "accuracy-cost" => /data-number=["']\d+\.7["']/,
    "binning" => /data-number=["']\d+\.8["']/
  }.each do |anchor, numbering|
    section = field_solver_html[/<section\s+id=["']#{Regexp.escape(anchor)}["'][\s\S]*?<\/section>/]
    errors << "field-solver ##{anchor} has incorrect automatic numbering" unless section&.match?(numbering)
  end
  errors << "field-solver does not suppress its duplicate margin TOC" unless field_solver_html.include?("opalx-sidebar-page-toc")
  errors << "field-solver sidebar lacks an accessible chapter toggle" unless field_solver_html.include?("Toggle Field Solver sections")
  errors << "field-solver sidebar lacks an accessible solver-type toggle" unless field_solver_html.include?("Toggle solver types")
  errors << "field-solver sidebar lacks accessible subsection toggles" unless field_solver_html.include?("Toggle ${item.text} subsections")
  errors << "field-solver sidebar does not label Binning" unless field_solver_html.include?('text: "Binning"')
  unless field_solver_html.scan(/<section\s+id=["']binning["']/).length == 1
    errors << "field-solver render must contain exactly one #binning section"
  end
  %w[
    page-toc:field-solver page-toc:field-solver:backends
    page-toc:field-solver:boundaries page-toc:field-solver:modes
  ].each do |state_key|
    errors << "field-solver sidebar is missing state key #{state_key}" unless field_solver_html.include?(state_key)
  end
else
  errors << "render is missing user-guide/field-solver/index.html"
end

elements_html_path = SITE / "user-guide/elements.html"
if elements_html_path.file?
  elements_html = File.read(elements_html_path)
  element_anchors = %w[
    common-element-syntax particle-removal drift collimator box beambeam constant-electric-field-cavity constant-focusing quadrupole multipole
    multipolet solenoid fieldmap rfcavity travelingwave cyclotronsector laser monitor marker probe bends
    scalingffamagnet variable-rf-cavity element-limitations
  ]
  element_anchors.each do |anchor|
    errors << "elements render is missing ##{anchor}" unless elements_html.match?(/\bid=["']#{Regexp.escape(anchor)}["']/)
  end
  {
    "common-element-syntax" => /data-number=["']\d+\.1["']/,
    "drift" => /data-number=["']\d+\.2["']/,
    "collimator" => /data-number=["']\d+\.3["']/,
    "box" => /data-number=["']\d+\.4["']/,
    "beambeam" => /data-number=["']\d+\.5["']/,
    "constant-electric-field-cavity" => /data-number=["']\d+\.6["']/,
    "constant-focusing" => /data-number=["']\d+\.7["']/,
    "fieldmap" => /data-number=["']\d+\.12["']/,
    "rfcavity" => /data-number=["']\d+\.13["']/,
    "travelingwave" => /data-number=["']\d+\.14["']/,
    "cyclotronsector" => /data-number=["']\d+\.15["']/,
    "laser" => /data-number=["']\d+\.16["']/,
    "bends" => /data-number=["']\d+\.20["']/,
    "scalingffamagnet" => /data-number=["']\d+\.\d+["']/,
    "variable-rf-cavity" => /data-number=["']\d+\.\d+["']/,
    "element-limitations" => /data-number=["']\d+\.\d+["']/
  }.each do |anchor, numbering|
    section = elements_html[/<section\s+id=["']#{Regexp.escape(anchor)}["'][\s\S]*?<\/section>/]
    errors << "elements ##{anchor} has incorrect automatic numbering" unless section&.match?(numbering)
  end
  errors << "elements does not suppress its duplicate margin TOC" unless elements_html.include?("opalx-sidebar-page-toc")
  errors << "elements sidebar lacks an accessible chapter toggle" unless elements_html.include?("Toggle Elements sections")
  errors << "elements sidebar state key is not rendered" unless elements_html.include?("page-toc:elements")
else
  errors << "render is missing user-guide/elements.html"
end

worked_inputs_html_path = SITE / "getting-started/worked-inputs.html"
if worked_inputs_html_path.file?
  worked_inputs_html = File.read(worked_inputs_html_path)
  {
    "example-drift" => /data-number=["']\d+\.1["']/,
    "example-rfcavity" => /data-number=["']\d+\.2["']/,
    "example-space-charge" => /data-number=["']\d+\.3["']/
  }.each do |anchor, numbering|
    section = worked_inputs_html[/<section\s+id=["']#{Regexp.escape(anchor)}["'][\s\S]*?<\/section>/]
    errors << "worked-inputs ##{anchor} has incorrect automatic numbering" unless section&.match?(numbering)
  end
else
  errors << "render is missing getting-started/worked-inputs.html"
end

input_language_html_path = SITE / "user-guide/input-language.html"
if input_language_html_path.file?
  input_language_html = File.read(input_language_html_path)
  %w[
    simulation-at-a-glance core-syntax parser-native-structures simulation-definitions
    beamline-definitions time-dependence-definitions tracking-block-structures executable-actions
    execution-order
  ].each do |anchor|
    errors << "input-language render is missing ##{anchor}" unless input_language_html.match?(/\bid=["']#{Regexp.escape(anchor)}["']/)
  end
  errors << "input-language render is missing its overview cards" unless input_language_html.include?("doc-grid")
else
  errors << "render is missing user-guide/input-language.html"
end

tracking_html_path = SITE / "user-guide/tracking.html"
if tracking_html_path.file?
  tracking_html = File.read(tracking_html_path)
  {
    "track-command" => /data-number=["']\d+\.1["']/,
    "run-command" => /data-number=["']\d+\.2["']/,
    "endtrack-command" => /data-number=["']\d+\.3["']/
  }.each do |anchor, numbering|
    section = tracking_html[/<section\s+id=["']#{Regexp.escape(anchor)}["'][\s\S]*?<\/section>/]
    errors << "tracking ##{anchor} is missing or incorrectly numbered" unless section&.match?(numbering)
  end
else
  errors << "render is missing user-guide/tracking.html"
end

physics_field_solver_html_path = SITE / "physics/field-solver/index.html"
if physics_field_solver_html_path.file?
  physics_field_solver_html = File.read(physics_field_solver_html_path)
  %w[
    field-solver-scope governing-electrostatic-model particle-mesh-discretization
    frames-transformations physics-boundary-conditions solver-formulations
    physics-binned-space-charge physics-emission-boundaries numerical-accuracy-convergence
    domain-decomposition field-solver-architecture field-solver-verification field-solver-limitations
  ].each do |anchor|
    errors << "physics field-solver render is missing ##{anchor}" unless physics_field_solver_html.match?(/\bid=["']#{Regexp.escape(anchor)}["']/)
  end
  errors << "physics field-solver HTML is missing its PNG diagram" unless physics_field_solver_html.include?("current-space-charge-class-diagram.png")
else
  errors << "render is missing physics/field-solver/index.html"
end

space_charge_architecture_html_path =
  SITE / "developer-guide/space-charge-solver-architecture.html"
if space_charge_architecture_html_path.file?
  space_charge_architecture_html = File.read(space_charge_architecture_html_path)
  %w[
    space-charge-architecture-overview space-charge-class-architecture
    space-charge-solver-flow
  ].each do |anchor|
    unless space_charge_architecture_html.match?(/\bid=["']#{Regexp.escape(anchor)}["']/)
      errors << "space-charge architecture render is missing ##{anchor}"
    end
  end
  %w[
    2026-09-07-opalx-space-charge-class-diagram.pdf
    2026-09-07-opalx-space-charge-solver-flow.pdf
  ].each do |document|
    unless space_charge_architecture_html.include?(document)
      errors << "space-charge architecture render is missing document link: #{document}"
    end
  end
  unless space_charge_architecture_html.scan(/class=["'][^"']*mermaid-js/).length == 2
    errors << "space-charge architecture render must contain exactly two Mermaid diagrams"
  end
else
  errors << "render is missing developer-guide/space-charge-solver-architecture.html"
end

reports_html_path = SITE / "resources/presentations-reports.html"
if reports_html_path.file?
  reports_html = File.read(reports_html_path)
  year_section = reports_html[/<section\s+id=["']reports-2026["'][^>]*>/]
  errors << "Presentations and Reports render is missing the 2026 section" unless year_section
  errors << "Presentations and Reports still numbers the 2026 section" if year_section&.include?("data-number=")
else
  errors << "render is missing resources/presentations-reports.html"
end

dual_pages = %w[
  user-guide/options.html
  user-guide/elements.html
  user-guide/diagnostics-output.html
  user-guide/beam.html
  user-guide/beam-distributions.html
  user-guide/field-solver/index.html
  user-guide/tracking.html
  user-guide/wakefields/index.html
  user-guide/geometry/index.html
  user-guide/particle-matter/index.html
  user-guide/optimization/index.html
  user-guide/sampler/index.html
  user-guide/appendix/field-maps/index.html
  user-guide/appendix/autophase/index.html
]
dual_pages.each do |relative|
  path = SITE / relative
  if !path.file?
    errors << "render is missing dual page #{relative}"
    next
  end
  html = File.read(path)
  errors << "#{relative} is missing rendered OPALX blocks" unless html.match?(/class=["'][^"']*feature-opalx(?:\s|["'])/)
  errors << "#{relative} is missing rendered OPAL blocks" unless html.match?(/class=["'][^"']*feature-opal(?:\s|["'])/)
end

shared_pages = %w[
  user-guide/introduction/index.html
  user-guide/input-language.html
  user-guide/command-format/index.html
  user-guide/control-statements/index.html
]
shared_pages.each do |relative|
  path = SITE / relative
  next unless path.file?
  html = File.read(path)
  if html.match?(/class=["'][^"']*feature-opalx(?:\s|["'])/) ||
     html.match?(/class=["'][^"']*feature-opal(?:\s|["'])/)
    errors << "shared page unexpectedly renders version blocks: #{relative}"
  end
end

beam_lines_html_path = SITE / "user-guide/beam-lines/index.html"
if beam_lines_html_path.file?
  beam_lines_html = File.read(beam_lines_html_path)
  errors << "beam-lines render is missing the OPALX RING geometry section" unless
    beam_lines_html.match?(/<section\s+id=["']ring-geometry-fringes["'][^>]*class=["'][^"']*feature-opalx(?:\s|["'])/)
else
  errors << "render is missing user-guide/beam-lines/index.html"
end

%w[
  user-guide/appendix/field-maps/index.html
  user-guide/appendix/language-syntax/index.html
  user-guide/appendix/autophase/index.html
].each do |relative|
  errors << "render is missing User Guide appendix #{relative}" unless (SITE / relative).file?
end

html_cache = {}

manual_html_files = html_files.reject { |path| path.to_s.start_with?("#{SITE}/api/") }

manual_html_files.each do |source|
  html = File.read(source)
  hrefs = html.scan(/\bhref\s*=\s*["']([^"']+)["']/i).flatten.map { |href| CGI.unescapeHTML(href) }

  hrefs.each do |href|
    next if href.empty? || href.start_with?("mailto:", "javascript:", "data:", "//")
    next if href.match?(/\A[a-z][a-z0-9+.-]*:/i)

    path_part, fragment = href.split("#", 2)
    path_part = path_part.to_s.split("?", 2).first.to_s
    target = if path_part.empty?
               source
             elsif path_part.start_with?("/")
               SITE / path_part.delete_prefix("/")
             else
               source.dirname / path_part
             end

    target = Pathname.new(target.to_s).cleanpath
    target = target / "index.html" if target.directory?
    target = Pathname.new("#{target}.html") if !target.exist? && target.extname.empty?

    unless target.to_s.start_with?("#{SITE}/") && target.file?
      errors << "#{source.relative_path_from(SITE)}: missing local target #{href}"
      next
    end

    next if fragment.nil? || fragment.empty? || target.extname.downcase != ".html"

    decoded_fragment = URI.decode_www_form_component(fragment)
    target_html = html_cache[target] ||= File.read(target)
    escaped = Regexp.escape(decoded_fragment)
    unless target_html.match?(/\b(?:id|name)\s*=\s*["']#{escaped}["']/i)
      errors << "#{source.relative_path_from(SITE)}: missing fragment ##{decoded_fragment} in #{target.relative_path_from(SITE)}"
    end
  end
end

unless errors.empty?
  errors.uniq.sort.each { |message| warn "error: #{message}" }
  abort "render validation failed with #{errors.uniq.length} error(s)"
end

puts "validated #{manual_html_files.length} rendered manual pages for the #{PROFILE} profile"
