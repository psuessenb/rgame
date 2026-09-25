# frozen_string_literal: true

# Every documentation page is reachable, every example and every house cop is
# described, and every link lands somewhere.
#
# These are the entries a new page, a new example or a renamed heading leaves
# stale. The lists are derived from the tree, not written down, so a new page or
# example is covered the day it is added.
RSpec.describe 'docs/api index and links' do # rubocop:disable RSpec/DescribeClass -- the subject is the documentation, not a class
  let(:readme) { File.join(ApiDocs::DIR, 'README.md') }

  it 'lists every page in the index' do
    linked = ApiDocs.links(readme).map { |_, target| target.split('#').first }
    pages = ApiDocs.pages.map { File.basename(it) } - ['README.md']

    expect(pages - linked).to be_empty
  end

  describe 'the examples page' do
    let(:described) { File.read(File.join(ApiDocs::DIR, 'examples.md')).scan(/^### (\S+)\s*$/).flatten }
    let(:examples) do
      Dir.children(File.join(ApiDocs::ROOT, 'examples'))
         .select { File.exist?(File.join(ApiDocs::ROOT, 'examples', it, 'main.rb')) }
    end

    it 'describes every example' do
      expect(examples - described).to be_empty
    end

    it 'describes no example that does not exist' do
      expect(described - examples).to be_empty
    end
  end

  it 'names every cop the RuboCop plugin ships on the CLI page' do
    cops = YAML.load_file(File.join(ApiDocs::ROOT, 'lib', 'rgame', 'rubocop', 'default.yml')).keys
    page = File.read(File.join(ApiDocs::DIR, 'cli.md'))

    expect(cops.reject { page.include?("`#{it}`") }).to be_empty
  end

  it 'has no link to a missing page or heading' do
    anchors = ApiDocs.pages.to_h { [File.basename(it), ApiDocs.anchors(it)] }

    broken = ApiDocs.pages.flat_map do |page|
      ApiDocs.links(page).filter_map do |line, target|
        file, fragment = target.split('#', 2)
        file = File.basename(page) if file.empty?
        exists = anchors.key?(file) || File.exist?(File.join(ApiDocs::DIR, file))
        next if exists && (fragment.nil? || anchors[file]&.include?(fragment))

        "#{File.basename(page)}:#{line} #{target}"
      end
    end

    expect(broken).to be_empty
  end
end
